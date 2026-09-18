use anyhow::anyhow;
use s3::{Auth, Client, types::ListBucketsOutput};

pub struct S3BucketStorage {
    client: Client,
}

impl S3BucketStorage {
    pub fn new(endpoint: &str, region: &str) -> anyhow::Result<Self> {
        Ok(Self {
            client: Client::builder(endpoint)?
                .region(region)
                .auth(Auth::from_env()?)
                .build()?,
        })
    }

    pub async fn list_buckets(&self) -> anyhow::Result<ListBucketsOutput> {
        self.client
            .buckets()
            .list()
            .send()
            .await
            .map_err(|r| anyhow!(r))
    }
}
