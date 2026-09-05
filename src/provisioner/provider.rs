use std::{collections::HashMap, ops::Deref};

use scaleway_rs::{ScalewayApi, ServerType};

pub struct Provider {
    api: ScalewayApi,
    zones: Vec<String>,
}

impl Provider {
    pub fn new() -> Self {
        let api_key = dotenv::var("SCW_SECRET_KEY")
            .expect("unable to initialize Scaleway provider: no SCW_SECRET_KEY in .env");
        let env_zones = dotenv::var("SCW_ZONE")
            .expect("unable to initialize Scaleway provider: no SCW_ZONE in .env");

        let zones: Vec<&str> = env_zones.split(" ").collect();
        assert!(
            !zones.is_empty(),
            "Scaleway zones are empty: either SCW_ZONE is malformed, or nothing was passed. Add all zones you want to check and separate with spaces"
        );

        Self {
            api: ScalewayApi::new(api_key),
            zones: zones.iter().map(|s| s.to_string()).collect(),
        }
    }

    pub fn get_cheapest_instance_type(self) -> anyhow::Result<ServerType> {
        let mut result: HashMap<String, ServerType> = HashMap::new();
        for z in self.zones {
            println!("checking zone: {}", z);
            for s in self.api.get_server_types(z)? {
                result.insert(s.id.to_string(), s);
            }
        }

        let mut list: Vec<ServerType> = result
            .into_values()
            .filter(|s| s.monthly_price.is_some())
            .collect();

        list.sort_by(|a, b| {
            a.monthly_price
                .unwrap()
                .total_cmp(&b.monthly_price.unwrap())
        });

        assert!(!list.is_empty(), "Failed to get instances from Scaleway");
        Ok(list.remove(0))
    }
}
