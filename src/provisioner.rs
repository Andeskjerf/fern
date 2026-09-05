use crate::provisioner::provider::Provider;

mod provider;

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

    pub fn provider(self) -> Provider {
        self.provider
    }
}
