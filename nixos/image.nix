{
  modulesPath,
  pkgs,
  config,
  lib,
  ...
}:

{
  imports = [
    (modulesPath + "/image/repart.nix")
  ];

  image.repart =
    let
      inherit (pkgs.stdenv.hostPlatform) efiArch;
    in
    {
      name = "image";

      partitions = {
        esp = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          repartConfig = {
            Format = "vfat";
            Label = "boot";
            SizeMinBytes = "200M";
            Type = "esp";
          };
        };
        nix-store = {
          storePaths = [ config.system.build.toplevel ];
          nixStorePrefix = "/";
          repartConfig = {
            Format = "squashfs";
            Label = "nix-store";
            Minimize = "guess";
            ReadOnly = "yes";
            Type = "linux-generic";
          };
        };
      };
    };
}
