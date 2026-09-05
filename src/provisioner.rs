use crate::provisioner::provider::Provider;

mod provider;
mod traits;

pub struct Provisioner {
    provider: Provider,
    worker_ips: Vec<u16>,
    controller_ip: Option<u16>,
}

impl Provisioner {
    pub fn new() -> Self {
        Self {
            provider: Provider::new(),
            worker_ips: vec![],
            controller_ip: Option::None,
        }
    }

    pub fn get_worker_ips(self) -> Vec<u16> {
        self.worker_ips
    }

    pub fn get_controller_ip(self) -> Option<u16> {
        self.controller_ip
    }

    pub fn create_instance(&mut self) -> anyhow::Result<()> {
        let provider = &mut self.provider;
        let mut instances = provider.get_instance_types()?;

        loop {
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

            if instances.is_empty() {
                panic!("Failed to create instance, no more instance options left");
            }
        }

        Ok(())
    }
}
