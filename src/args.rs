use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
pub struct Args {
    pub image_path: String,

    #[arg(short, long)]
    pub dryrun: bool,

    #[arg(short, long)]
    pub zone: Option<String>,

    #[arg(short, long)]
    pub instance_type: Option<String>,
}
