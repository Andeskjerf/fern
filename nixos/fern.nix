{ fern }:
{
  pkgs,
  lib,
  config,
  ...
}:
{
  # read-only squashfs store: no nix daemon, no overlayfs
  not-os.nix = false;

  # af_packet: dhcpcd needs AF_PACKET, the kernel builds it as a module and
  # nothing else would ever load it (no modprobe in stage 2)
  boot.initrd.kernelModules = [
    "af_packet"
    "virtio"
    "virtio_pci"
    "virtio_net"
    "virtio_rng"
    "virtio_blk"
    "virtio_console"
  ];

  boot.kernelParams = [ "console=ttyS0" ];
  boot.postBootCommands = ''
    mkdir -p /var/lib/fern
  '';

  environment.systemPackages = [
    fern
    pkgs.dhcpcd
  ];

  environment.etc = lib.mkMerge [
    {
      # qemu user-mode resolver; Scaleway deployments need their own resolver here
      "resolv.conf".text =
        "nameserver "
        + lib.concatMapStringsSep "." toString [
          10
          0
          2
          3
        ];
      "dhcpcd.conf".text = ''
        hostname fern
        interface eth0
      '';
    }
    {
      "service/net/run".source = pkgs.writeScript "net-run" ''
        #!${pkgs.runtimeShell}
        mkdir -p /var/run/dhcpcd
        # dhcpcd hooks update /etc/resolv.conf, which sits on the read-only
        # etc mount; bind a writable file over it so leases reach the resolver
        touch /run/resolv.conf
        mount --bind /run/resolv.conf /etc/resolv.conf
        exec dhcpcd -B eth0
      '';
      "service/fern/run".source = pkgs.writeScript "fern-run" ''
        #!${pkgs.runtimeShell}
        # fern reads SCW_* via dotenv from cwd, which is meaningless under runsv;
        # /var/lib/fern/env (KEY=VALUE lines) is the service-level substitute.
        echo "fern: starting" > /dev/console
        if [ -f /var/lib/fern/env ]; then
          set -a
          . /var/lib/fern/env
        fi
        exec fern > /dev/console 2>&1
      '';
    }
    {
      # slim stage 1: no ssh-keygen, no ntpdate
      "runit/1".source = lib.mkForce (
        pkgs.writeScript "runit-1" ''
          #!${pkgs.runtimeShell}
          echo fern > /proc/sys/kernel/hostname
          mkdir /bin/
          ln -s ${pkgs.runtimeShell} /bin/sh
          touch /etc/runit/stopit
          chmod 0 /etc/runit/stopit
        ''
      );
      "service/sshd/run".enable = false;
      "service/nix/run".enable = false;
    }
  ];

  # replaces the scaffold's perl setup-etc: / is a fresh tmpfs at boot, so
  # mirroring the etc tree is all the activation needs — real writable dirs
  # (runsv needs to create supervise/ inside service dirs) and files symlinked
  # through /etc/static; keeps perl out of the image
  system.activationScripts.etc = lib.mkForce (
    lib.stringAfter [ "users" "groups" ] ''
      TREE="${config.system.build.etc}/etc"
      ln -sfn "$TREE" /etc/static
      find "$TREE" -mindepth 1 -type d | while read -r dir; do
        mkdir -p "/etc/''${dir#"$TREE"/}"
      done
      find "$TREE" -mindepth 1 ! -type d | while read -r file; do
        ln -sfn "/etc/static/''${file#"$TREE"/}" "/etc/''${file#"$TREE"/}"
      done
    ''
  );
}
