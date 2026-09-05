use scaleway_rs::ServerType;

use crate::provisioner::provider::Provider;

mod provider;
mod traits;

pub struct Provisioner {
    provider: Provider,
    worker_instance_ids: Vec<String>,
    controller_instance_id: Option<String>,
}

impl Provisioner {
    pub fn new() -> Self {
        Self {
            provider: Provider::new(),
            worker_instance_ids: vec![],
            controller_instance_id: Option::None,
        }
    }

    pub fn create_instance(&mut self, instance_type: Option<&str>) -> anyhow::Result<()> {
        let provider = &mut self.provider;
        // TODO: should be a generic
        let mut instances: Vec<ServerType> = match instance_type.is_none() {
            true => provider.get_instance_types()?,
            false => vec![provider.get_instance_type(instance_type.unwrap())?],
        };

        loop {
            if instances.is_empty() {
                panic!("Failed to create instance, no more instance options left");
            }

            // we get the first, that's the cheapest one
            let instance = instances.remove(0);

            let instance_id = provider.create_instance(
                &instance.location,
                "test",
                &instance.id,
                "Ubuntu 26.04 Resolute Raccoon",
                instance.arch.as_str(),
            );

            if let Ok(id) = instance_id {
                println!("Success!\n{:?}\nCleaning up", id);
                provider.cleanup_instance(&instance.location, &id)?;
                break;
            } else {
                println!(
                    "Failed to create instance with ID={}, trying next option",
                    instance.id
                )
            }
        }

        Ok(())
    }
}
