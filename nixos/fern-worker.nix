{
  modulesPath,
  default,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/image-based-appliance.nix")
    (modulesPath + "/profiles/perlless.nix")
    ./filesystems.nix
    ./image.nix
    ./inflate.nix
    ./space-savings.nix
  ];

  # system.forbiddenDependenciesRegexes = lib.mkForce [];

  # Include Fern binary
  environment.systemPackages = [ default ];

  system.stateVersion = "26.11";

  boot.loader.grub.enable = false;

  services.getty.autologinUser = "root";
  users.users.root.initialPassword = "";
}
