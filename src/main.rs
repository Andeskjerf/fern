use crate::{args::Args, provisioner::Provisioner};
use clap::Parser;

mod args;
mod provisioner;

fn dryrun(provisioner: &mut Provisioner) -> anyhow::Result<String> {
    let instance_id = provisioner.try_create_cheapest_instance_type(
        "test",
        "Ubuntu 26.04 Resolute Raccoon",
        None,
    )?;

    let instance_json = provisioner
        .get_instance_by_id(&instance_id)
        .ok_or_else(|| anyhow::anyhow!("instance {instance_id} not found"))?
        .to_json();

    provisioner.cleanup(&instance_id)?;
    Ok(instance_json)
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    let mut provisioner = Provisioner::new();
    if args.dryrun {
        println!("{}", dryrun(&mut provisioner)?);
    }

    Ok(())
}
