{
  # hardware.enableRedistributableFirmware = false;

  services.openssh.enable = false;

  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
  ];

  networking.firewall.enable = false;

  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
}
