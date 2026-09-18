use s3::{Auth, BlockingClient, types::ListBucketsOutput};

const BUCKET_NAME: &str = "fern_fleet_of_ephemeral_runtime_nodes";

pub struct S3BucketStorage {
    client: BlockingClient,
}

impl S3BucketStorage {
    pub fn new(endpoint: &str, region: &str) -> anyhow::Result<Self, s3::Error> {
        let mut storage = Self {
            client: BlockingClient::builder(endpoint)?
                .region(region)
                .auth(Auth::from_env()?)
                .build()?,
        };

        storage.init()?;

        Ok(storage)
    }

    fn init(&mut self) -> anyhow::Result<(), s3::Error> {
        let buckets = self.list_buckets()?;
        let bucket_exists = buckets.buckets.iter().any(|b| b.name == BUCKET_NAME);

        if !bucket_exists {
            println!("Bucket does not exist at hosting provider, creating new one...");
            self.client.buckets().create(BUCKET_NAME).send()?;
        }

        Ok(())
    }

    fn list_buckets(&self) -> anyhow::Result<ListBucketsOutput, s3::Error> {
        self.client.buckets().list().send()
    }

    pub fn list_images(&self) -> anyhow::Result<Vec<String>> {
        let result = self.client.objects().list_v2(BUCKET_NAME).send()?;
        println!("{:?}", result);
        Ok(vec![])
    }
}
