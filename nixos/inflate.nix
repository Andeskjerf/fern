{
  boot.initrd.systemd.repart.enable = true;
  boot.initrd.systemd.repart.device = "/dev/sda";
  systemd.repart.partitions = {
    home = {
      Format = "ext4";
      Label = "home";
      Type = "home";
      Weight = 2000;
    };
    var = {
      Format = "ext4";
      Label = "var";
      Type = "var";
      Weight = 1000;
    };
  };
}
