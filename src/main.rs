use crate::{args::Args, provisioner::Provisioner};
use clap::Parser;

mod args;
mod provisioner;
mod storage;

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    let mut provisioner = Provisioner::new();
    if args.dryrun {
        println!("{}", provisioner.dryrun(&args)?);
        return Ok(());
    }

    Ok(())
}
