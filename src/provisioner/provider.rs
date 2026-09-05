use std::collections::HashMap;

use scaleway_rs::{ScalewayApi, ScalewayError, ScalewayImage, ScalewayInstance, ServerType};

use crate::provisioner::traits::has_id::HasId;

pub struct Provider {
    api: ScalewayApi,
    project: String,
    zones: Vec<String>,
    instances: HashMap<String, ScalewayInstance>,
}

impl Provider {
    pub fn new() -> Self {
        let api_key = dotenv::var("SCW_SECRET_KEY")
            .expect("unable to initialize Scaleway provider: no SCW_SECRET_KEY in .env");
        let env_zones = dotenv::var("SCW_ZONES")
            .expect("unable to initialize Scaleway provider: no SCW_ZONES in .env");
        let project = dotenv::var("SCW_DEFAULT_PROJECT_ID")
            .expect("unable to initialize Scaleway provider: no SCW_DEFAULT_PROJECT_ID in .env");

        let zones: Vec<&str> = env_zones.split(" ").collect();
        assert!(
            !zones.is_empty(),
            "Scaleway zones are empty: either SCW_ZONE is malformed, or nothing was passed. Add all zones you want to check and separate with spaces"
        );

        Self {
            api: ScalewayApi::new(api_key),
            zones: zones.iter().map(|s| s.to_string()).collect(),
            project,
            instances: HashMap::new(),
        }
    }

    fn get_options_for_all_zones<T: HasId>(
        zones: &Vec<String>,
        func: impl Fn(&str) -> Result<Vec<T>, ScalewayError>,
    ) -> anyhow::Result<Vec<T>> {
        let mut result: HashMap<String, T> = HashMap::new();
        for z in zones {
            let func_value = func(z)?;
            for i in func_value {
                result.insert(i.id().to_string(), i);
            }
        }
        Ok(result.into_values().collect::<Vec<T>>())
    }

    pub fn get_images(&self) -> anyhow::Result<Vec<ScalewayImage>> {
        let mut result = Provider::get_options_for_all_zones::<ScalewayImage>(&self.zones, |z| {
            self.api.list_images(z).run()
        })?;
        result.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(result)
    }

    pub fn get_instance_types(&self) -> anyhow::Result<Vec<ServerType>> {
        let mut result: Vec<ServerType> =
            Provider::get_options_for_all_zones::<ServerType>(&self.zones, |z| {
                self.api.get_server_types(z)
            })?
            .into_iter()
            .filter(|s| s.monthly_price.is_some())
            .collect();

        result.sort_by(|a, b| {
            a.monthly_price
                .unwrap()
                .total_cmp(&b.monthly_price.unwrap())
        });

        Ok(result)
    }

    pub fn get_instance_type(&self, instance_id: &str) -> anyhow::Result<ServerType> {
        Ok(self
            .get_instance_types()?
            .into_iter()
            .find(|i| i.id == instance_id)
            .expect(&format!("Could not find instance with ID: {}", instance_id)))
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
        Provider::assert_image_in_list(&valid_images, image_name);
        let image = Provider::find_matching_image(&valid_images, zone, image_name, arch);

        let instance = self
            .api
            .create_instance(zone, name, instance_id)
            .image(&image.id)
            .project(&self.project)
            .run()?;

        let instance_id = instance.id.clone();
        self.instances.insert(instance_id.clone(), instance);
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

        if instance.unwrap().state != "stopped" {
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
                self.instances.remove(server_id);
                Ok(())
            }
            Err(err) => Err(err.into()),
        }
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
