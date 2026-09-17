use std::ops::Deref;

use scaleway_rs::ScalewayInstance;
use serde::{Serialize, Serializer, ser::SerializeStruct};

pub trait InstanceFields {
    fn zone(&self) -> &str;
    fn id(&self) -> &str;
}

pub struct Instance<T>(pub T);

impl<T> Deref for Instance<T> {
    type Target = T;

    fn deref(&self) -> &T {
        &self.0
    }
}

impl Serialize for Instance<ScalewayInstance> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut state = serializer.serialize_struct("Instance", 2)?;
        state.serialize_field("id", &self.0.id)?;
        state.serialize_field("zone", &self.0.zone)?;
        state.end()
    }
}

pub trait ProviderInstance {
    fn zone(&self) -> &str;
    fn id(&self) -> &str;
    fn to_json(&self) -> String;
}

impl ProviderInstance for Instance<ScalewayInstance> {
    fn zone(&self) -> &str {
        self.0.zone()
    }
    fn id(&self) -> &str {
        self.0.id()
    }

    fn to_json(&self) -> String {
        serde_json::to_string(self).expect("serialize instance")
    }
}

impl InstanceFields for scaleway_rs::ScalewayInstance {
    fn id(&self) -> &str {
        &self.id
    }

    fn zone(&self) -> &str {
        &self.zone
    }
}
