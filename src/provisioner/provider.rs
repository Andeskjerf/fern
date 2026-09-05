use std::collections::HashMap;

use scaleway_rs::{ScalewayApi, ScalewayError, ScalewayImage, ServerType};

use crate::provisioner::traits::has_id::HasId;

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

    pub fn get_images(self) -> anyhow::Result<Vec<ScalewayImage>> {
        let mut result = Provider::get_options_for_all_zones::<ScalewayImage>(&self.zones, |z| {
            self.api.list_images(z).run()
        })?;
        result.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(result)
    }

    pub fn get_cheapest_instance_type(self) -> anyhow::Result<ServerType> {
        let mut result = Provider::get_options_for_all_zones::<ServerType>(&self.zones, |z| {
            self.api.get_server_types(z)
        })?;
        result.sort_by(|a, b| {
            a.monthly_price
                .unwrap()
                .total_cmp(&b.monthly_price.unwrap())
        });

        assert!(!result.is_empty(), "Failed to get instances from Scaleway");
        Ok(result.remove(0))
    }
}
