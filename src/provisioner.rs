use scaleway_rs::ServerType;

use crate::provisioner::{
    scaleway_provider::ScalewayProvider, traits::provider_instance::ProviderInstance,
};

mod scaleway_provider;
mod traits;

pub struct Provisioner {
    provider: ScalewayProvider,
}

impl Provisioner {
    pub fn new() -> Self {
        Self {
            provider: ScalewayProvider::new(),
        }
    }

    pub fn upload_image(&self) -> anyhow::Result<()> {
        Ok(())
    }

    pub fn get_instance_by_id(&self, id: &str) -> Option<&dyn ProviderInstance> {
        self.provider.get_created_instance(id)
    }

    pub fn cleanup(&mut self, id: &str) -> anyhow::Result<()> {
        let zone = self
            .provider
            .get_created_instance(id)
            .map(|z| z.zone().to_string());

        match zone {
            Some(zone) => self.provider.cleanup_instance(&zone, id),
            _ => {
                println!("Could not cleanup ID '{}': not found", id);
                Ok(())
            }
        }
    }

    pub fn try_create_cheapest_instance_type(
        &mut self,
        instance_name: &str,
        image_name: &str,
        instance_type: Option<String>,
        zone: Option<String>,
    ) -> anyhow::Result<String> {
        let provider = &mut self.provider;
        // TODO: should be a generic
        let mut instances: Vec<ServerType> = match instance_type.is_none() {
            true => provider.get_instance_types(zone)?,
            false => vec![provider.get_instance_type(&instance_type.unwrap(), zone)?],
        };

        loop {
            if instances.is_empty() {
                panic!("Failed to create instance, no more instance options left");
            }

            // we get the first, that's the cheapest one
            let instance = instances.remove(0);
            let instance_id = provider.create_instance(
                &instance.location,
                instance_name,
                &instance.id,
                image_name,
                instance.arch.as_str(),
            );

            if let Ok(id) = instance_id {
                println!("Created instance with ID: {:?}", id);
                return Ok(id);
            } else {
                println!(
                    "Failed to create instance with ID={}, trying next option",
                    instance.id
                )
            }
        }
    }
}
