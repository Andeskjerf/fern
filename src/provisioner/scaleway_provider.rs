use std::collections::HashMap;

use anyhow::anyhow;
use scaleway_rs::{
    ScalewayApi, ScalewayError, ScalewayImage, ScalewayInstance, ScalewayVolume, ServerType,
};

use crate::provisioner::traits::has_id::HasId;
use crate::provisioner::traits::provider_instance::{Instance, ProviderInstance};
use crate::storage::s3_bucket::S3BucketStorage;

const SCALEWAY_ZONES: [&str; 8] = [
    "fr-par-1", "fr-par-2", "nl-ams-1", "nl-ams-2", "nl-ams-3", "pl-waw-1", "pl-waw-2", "pl-waw-3",
];

// TODO: add generic trait for `Provider`
pub struct ScalewayProvider {
    api: ScalewayApi,
    project: String,
    instances: HashMap<String, Instance<ScalewayInstance>>,
    s3: Option<S3BucketStorage>,
}

impl ScalewayProvider {
    pub fn new() -> Self {
        let api_key = dotenv::var("SCW_SECRET_KEY")
            .expect("unable to initialize Scaleway provider: no SCW_SECRET_KEY in .env");
        let project = dotenv::var("SCW_DEFAULT_PROJECT_ID")
            .expect("unable to initialize Scaleway provider: no SCW_DEFAULT_PROJECT_ID in .env");

        Self {
            api: ScalewayApi::new(api_key),
            project,
            instances: HashMap::new(),
            s3: None, // init later once we know what zone we're using
        }
    }

    fn init_s3(&mut self, zone: &str) -> anyhow::Result<()> {
        if self.s3.is_some() {
            return Err(anyhow!(
                "Unable to initialize Scaleway provider with S3: already initialized"
            ));
        }

        self.s3 = Some(S3BucketStorage::new("scw.cloud", zone)?);
        Ok(())
    }

    fn get_options_for_all_zones<T: HasId>(
        func: impl Fn(&str) -> Result<Vec<T>, ScalewayError>,
    ) -> anyhow::Result<Vec<T>> {
        let mut result: HashMap<String, T> = HashMap::new();
        for z in SCALEWAY_ZONES {
            let func_value = func(z)?;
            for i in func_value {
                result.insert(i.id().to_string(), i);
            }
        }
        Ok(result.into_values().collect::<Vec<T>>())
    }

    pub fn get_created_instance(&self, id: &str) -> Option<&dyn ProviderInstance> {
        self.instances.get(id).map(|i| i as &dyn ProviderInstance)
    }

    fn get_images(&self) -> anyhow::Result<Vec<ScalewayImage>> {
        let mut result = ScalewayProvider::get_options_for_all_zones::<ScalewayImage>(|z| {
            self.api.list_images(z).run()
        })?;
        result.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(result)
    }

    pub fn get_instance_types(&self, zone: Option<String>) -> anyhow::Result<Vec<ServerType>> {
        let mut result: Vec<ServerType> =
            ScalewayProvider::get_options_for_all_zones::<ServerType>(|z| {
                self.api.get_server_types(z)
            })?
            .into_iter()
            .filter(|s| zone.is_none() || zone.as_ref().is_some_and(|z| s.location == *z))
            .filter(|s| s.monthly_price.is_some())
            .collect();

        result.sort_by(|a, b| {
            a.monthly_price
                .unwrap()
                .total_cmp(&b.monthly_price.unwrap())
        });

        Ok(result)
    }

    pub fn get_instance_type(
        &self,
        instance_id: &str,
        zone: Option<String>,
    ) -> anyhow::Result<ServerType> {
        Ok(self
            .get_instance_types(zone)?
            .into_iter()
            .find(|i| i.id == instance_id)
            .expect(&format!("Could not find instance with ID: {}", instance_id)))
    }

    pub fn get_volumes(&self) -> anyhow::Result<Vec<ScalewayVolume>> {
        ScalewayProvider::get_options_for_all_zones(|z| self.api.list_volumes(z).run())
    }

    pub fn create_instance(
        &mut self,
        zone: &str,
        name: &str,
        instance_id: &str,
        image_name: &str,
        arch: &str,
    ) -> anyhow::Result<String> {
        let valid_images = self.get_images()?;
        ScalewayProvider::assert_image_in_list(&valid_images, image_name);
        let image = ScalewayProvider::find_matching_image(&valid_images, zone, image_name, arch);

        let instance = self
            .api
            .create_instance(zone, name, instance_id)
            .image(&image.id)
            .project(&self.project)
            .run()?;

        let instance_id = instance.id.clone();
        self.instances
            .insert(instance_id.clone(), Instance(instance));
        Ok(instance_id)
    }

    pub fn cleanup_instance(&mut self, zone: &str, server_id: &str) -> anyhow::Result<()> {
        let instance = self.instances.get(server_id);
        if instance.is_none() {
            println!(
                "Could not cleanup instance: No instance with ID {}",
                server_id
            );
            return Ok(());
        }
        let instance = instance.unwrap();

        if instance.state != "stopped" {
            match self.api.perform_instance_action(
                zone,
                server_id,
                scaleway_rs::InstanceAction::Poweroff,
            ) {
                Ok(_) => (),
                Err(err) => panic!("{:?}", err),
            }
        }

        match self.api.delete_instance(zone, server_id) {
            Ok(_) => {
                println!("Instance deleted: {}", instance.id);
                self.cleanup_detached_volumes()?;
                self.instances.remove(server_id);
                Ok(())
            }
            Err(err) => Err(err.into()),
        }
    }

    pub fn cleanup_detached_volumes(&self) -> anyhow::Result<()> {
        self.get_volumes()?
            .iter()
            .filter(|v| v.server.is_none())
            .for_each(|v| match self.api.delete_volume(&v.zone, &v.id) {
                Ok(_) => println!("Volume deleted: {}, {}", v.name, v.id),
                Err(err) => eprintln!("Failed to delete volume={}: {}", v.id, err),
            });
        Ok(())
    }

    fn find_matching_image<'a>(
        valid_images: &'a [ScalewayImage],
        zone: &str,
        image_name: &'a str,
        arch: &str,
    ) -> &'a ScalewayImage {
        valid_images
            .iter()
            .find(|i| i.name == image_name && i.arch == arch && i.zone == zone)
            .unwrap_or_else(|| {
                panic!(
                    "Could not find any images with given name={} & arch={}",
                    image_name, arch
                )
            })
    }

    fn assert_image_in_list(valid_images: &[ScalewayImage], image_name: &str) {
        if !valid_images.iter().any(|i| i.name == image_name) {
            panic!(
                "image={}. Image was not found in provider list of valid images",
                image_name
            );
        }
    }
}
