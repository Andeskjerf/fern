use std::path::Path;

use crate::{args::Args, provisioner::Provisioner};
use clap::Parser;

mod args;
mod provisioner;
mod storage;

fn validate_args(args: &Args) {
    if !Path::new(&args.image_path).exists() {
        panic!("Given image_path does not exist! - {}", args.image_path);
    }
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    validate_args(&args);

    let mut provisioner = Provisioner::new(args.image_path.clone());
    if args.dryrun {
        println!("{}", provisioner.dryrun(&args)?);
        return Ok(());
    }

    provisioner.has_image_changed()?;

    Ok(())
}
