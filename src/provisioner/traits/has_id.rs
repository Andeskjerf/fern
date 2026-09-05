pub trait HasId {
    fn id(&self) -> &str;
}

impl HasId for scaleway_rs::ServerType {
    fn id(&self) -> &str {
        &self.id
    }
}

impl HasId for scaleway_rs::ScalewayImage {
    fn id(&self) -> &str {
        &self.id
    }
}

impl HasId for scaleway_rs::ScalewayVolume {
    fn id(&self) -> &str {
        &self.id
    }
}
