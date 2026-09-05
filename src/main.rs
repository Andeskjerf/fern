use crate::provisioner::Provisioner;

mod provisioner;

fn main() -> anyhow::Result<()> {
    let provisioner = Provisioner::new();

    // let cheapest_instance = provisioner.provider().get_cheapest_instance_type()?;
    // println!("{:?}", cheapest_instance);

    provisioner.provider().get_images()?;


    Ok(())
}
