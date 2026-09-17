{ fern, appliance }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # static busybox for the pre-pivot init: the raw squashfs root has no
  # /nix/store, so a dynamically linked busybox would fail to exec (its
  # glibc interpreter path does not exist until the pivot mounts the store)
  initBusybox = pkgs.pkgsStatic.busybox;

  # absolute shebang interpreter for everything post-pivot: keeps bash
  # (and its glibc closure) out of the image entirely
  sh = "${initBusybox}/bin/sh";

  # udhcpc event hook (replaces the glibc-linked dhcpcd): busybox udhcpc
  # calls it with $1 in deconfig|bound|renew and lease details in env vars.
  # /run/resolv.conf is the writable side of the bind-mount over the
  # read-only /etc/resolv.conf (see net-run)
  udhcpcHook = pkgs.writeScript "udhcpc-hook" ''
    #!${sh}
    case "$1" in
      deconfig)
        ifconfig "$interface" 0.0.0.0
        ;;
      bound|renew)
        ifconfig "$interface" "$ip" netmask "''${subnet:-${
          lib.concatMapStringsSep "." toString [
            255
            255
            255
            0
          ]
        }}"
        while route del default dev "$interface" 2>/dev/null; do :; done
        for r in ''${router:-}; do
          route add default gw "$r" dev "$interface"
        done
        : > /run/resolv.conf
        for d in ''${dns:-}; do
          echo "nameserver $d" >> /run/resolv.conf
        done
        # lease with no resolver info: fall back to the static qemu resolver
        [ -s /run/resolv.conf ] || echo "nameserver ${
          lib.concatMapStringsSep "." toString [
            10
            0
            2
            3
          ]
        }" > /run/resolv.conf
        ;;
    esac
  '';

  # PID1 for the initrd-free boot: the kernel mounts the read-only squashfs
  # root directly and fern-init pivots into a tmpfs with the store mounted
  # inside, mirroring what not-os stage 1 did, then hands over to stage 2.
  #
  # Path gotcha: make-squashfs puts every store path at the image ROOT (the
  # image is meant to be mounted *as* /nix/store). So pre-pivot, everything
  # resolves at /<basename>; /nix/store/<...> only exists after the pivot.
  # The shebang and PATH use the basename form; the exec of stage 2 happens
  # after the pivot and uses the regular store path. /dev, /proc and /new
  # anchor dirs are baked into the squashfs (see system.build.squashfs);
  # root= comes from the boot loader, /dev/vda2 by default.
  busyboxName = baseNameOf initBusybox;
  initScript = pkgs.writeScript "fern-init" ''
    #!/${busyboxName}/bin/sh
    set -e
    PATH=/${busyboxName}/bin:/nix/store/${busyboxName}/bin
    mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
    mountpoint -q /proc || mount -t proc proc /proc
    root=/dev/vda2
    for o in $(cat /proc/cmdline); do
      case $o in root=*) root=''${o#root=};; esac
    done
    mount -t tmpfs -o size=1G,mode=0755 root /new
    mkdir -p /new/nix/store /new/old
    # -o ro: the same device is already mounted ro as the root fs; busybox
    # would otherwise try rw and get "would change RO state" -> EBUSY
    mount -t squashfs -o ro "$root" /new/nix/store
    pivot_root /new /new/old
    umount -l /old || true
    # exec the toplevel's init (not bootStage2): base.nix substitutes
    # @systemConfig@ into that copy, and it's in the squashfs via toplevel
    exec ${config.system.build.toplevel}/init
  '';
in
{
  # read-only squashfs store: no nix daemon, no overlayfs
  not-os.nix = false;

  # af_packet/virtio/squashfs all builtin; the initrd is dropped entirely
  # (kernel boots straight into fern-init), so there is no stage 1 left
  boot.initrd.kernelModules = [ ];

  # pruned kernel: allnoconfig base (enableCommonConfig=false +
  # defconfig="allnoconfig", autoModules=false) plus only what the boot path
  # needs — defconfig's SATA/SCSI/NVMe/DRM/USB/WLAN/E1000 bloat is unused
  # under qemu virtio and never enters the config. EXPERT stays off, so the
  # default-on userspace knobs (shmem, membarrier, posix timers...) survive
  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.buildLinux rec {
      version = "6.18.34";
      modDirVersion = version;
      src = pkgs.linuxPackages.kernel.src;
      kernelPatches = [ ];
      enableCommonConfig = false;
      defconfig = "allnoconfig";
      autoModules = false;
      ignoreConfigErrors = true;
      structuredExtraConfig = with lib.kernel; {
        # boot path
        PCI = yes;
        PCI_MSI = yes;
        VIRTIO_MENU = yes; # menuconfig gate for VIRTIO_PCI etc, allnoconfig kills it
        VIRTIO = yes;
        VIRTIO_PCI = yes;
        VIRTIO_BLK = yes;
        VIRTIO_NET = yes;
        PARAVIRT = yes;
        HYPERVISOR_GUEST = yes; # gate for PARAVIRT/KVM_GUEST, allnoconfig kills it
        KVM_GUEST = yes;
        # networking (PACKET = AF_PACKET for dhcpcd)
        NET = yes;
        INET = yes;
        PACKET = yes;
        UNIX = yes;
        NETDEVICES = yes;
        # root fs + serial console (MISC_FILESYSTEMS gates SQUASHFS)
        MISC_FILESYSTEMS = yes;
        SQUASHFS = yes;
        SQUASHFS_XZ = yes;
        DEVTMPFS = yes;
        DEVTMPFS_MOUNT = yes;
        TMPFS = yes;
        PROC_FS = yes;
        SYSFS = yes;
        TTY = yes;
        UNIX98_PTYS = yes;
        SERIAL_8250 = yes;
        SERIAL_8250_CONSOLE = yes;
        # userspace basics
        PRINTK = yes;
        BINFMT_ELF = yes;
        BINFMT_SCRIPT = yes;
        BLOCK = yes;
        BLK_DEV = yes;
        MMU = yes;
        SMP = yes;
        MULTIUSER = yes;
        FUTEX = yes;
        EPOLL = yes;
        EVENTFD = yes;
        TIMERFD = yes;
        HW_RANDOM = yes;
        HW_RANDOM_VIRTIO = yes;
        # size
        KERNEL_XZ = yes;
        CC_OPTIMIZE_FOR_SIZE = yes;
        # MODULES must stay on: nixpkgs buildLinux hardcodes CONFIG_MODULES=y
        # into its postInstall (isModular), which runs modules_install and then
        # unlinks the build symlink that only exists when modules are enabled.
        # autoModules=false keeps the tree empty, so this costs ~50 KiB.
        MODULES = yes;
        BLK_DEV_INITRD = no;
        WERROR = no;
      };
    }
  );

  boot.kernelParams = lib.mkForce [
    "console=ttyS0"
    "rootfstype=squashfs"
    # basename form: the root fs *is* the store, store paths live at its root
    "init=/${baseNameOf initScript}"
  ];

  # stage 2 with a busybox sh shebang (upstream is generated with
  # pkgs.runtimeShell = bash, which would pin glibc into the closure);
  # local-cmds gets the same treatment — upstream wraps it in
  # writeShellScript, another bash reference
  system.build.bootStage2 = lib.mkForce (
    pkgs.replaceVarsWith {
      src = appliance + "/stage-2-init.sh";
      isExecutable = true;
      replacements = {
        path = config.system.path;
        runtimeShell = sh;
        # null keeps @systemConfig@ in the file; toplevel fills it in later.
        systemConfig = null;
        postBootCommands = pkgs.writeScript "local-cmds" ''
          #!${sh}
          ${config.boot.postBootCommands}
        '';
      };
    }
  );
  # /var is a fresh tmpfs at every boot: the scaffold's var script runs
  # e2fsprogs chattr on /var/empty (pulling the whole e2fsprogs closure incl.
  # libarchive/openssl into the image) and find -delete on an empty dir —
  # both pointless here, so replace it with plain mkdir/chmod (mkOverride
  # beats the scaffold's own mkForce); also covers /var/lib/fern
  system.activationScripts.var = lib.mkOverride 25 ''
    mkdir -p /var/tmp /var/empty /var/lib/fern
    chmod 1777 /var/tmp
    chmod 0555 /var/empty
  '';

  # /usr/bin/env must not come from coreutils (see the activation-PATH patch)
  environment.usrbinenv = "${pkgs.pkgsStatic.busybox}/bin/env";

  boot.postBootCommands = lib.mkForce "";

  # lean userland: util-linux and iproute2 audited unreferenced (the `ip`
  # users live in the disabled simpleStaticIp branch); the scaffold's nixpkgs
  # is patched to drop util-linux/shadow from the activation PATH, and busybox
  # covers mount/umount/swapoff/ping. mkForce drops the scaffold's hardcoded
  # requiredPackages (util-linux, iproute2)
  environment.systemPackages = lib.mkForce [
    fern
    pkgs.pkgsStatic.busybox
    # static so glibc leaves the squashfs; the only glibc referrer left
    pkgs.pkgsStatic.runit
  ];

  environment.etc = lib.mkMerge [
    {
      # not-os always generates a nix/nix.conf whose builder depends on the
      # bash closure (writeClosure [ pkgs.bash ]): pointless with the nix
      # daemon disabled and drags bash-interactive+ncurses+readline into the
      # image — replace with an empty file
      "nix/nix.conf" = lib.mkForce { text = ""; };
      # port/service name lookups: nothing in the image reads these
      # (fern resolves ports numerically, busybox doesn't consult them)
      "services".source = lib.mkForce pkgs.emptyFile;
      # qemu user-mode resolver; Scaleway deployments need their own resolver here
      "resolv.conf".text =
        "nameserver "
        + lib.concatMapStringsSep "." toString [
          10
          0
          2
          3
        ];
      # fern's rustls-native-certs reads ca-certificates.crt only
      "ssl/certs/ca-bundle.crt".source = lib.mkForce pkgs.emptyFile;
    }
    {
      "service/net/run".source = pkgs.writeScript "net-run" ''
        #!${sh}
        # dhcpcd hooks updated /etc/resolv.conf, which sits on the read-only
        # etc mount; bind a writable file over it so leases reach the resolver
        touch /run/resolv.conf
        mount --bind /run/resolv.conf /etc/resolv.conf
        exec udhcpc -f -i eth0 -s ${udhcpcHook}
      '';
      "service/fern/run".source = pkgs.writeScript "fern-run" ''
        #!${sh}
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
      # slim runit stages: shebangs pin to busybox sh so bash never enters
      # the closure; stage 3 is also POSIX-ified — upstream uses pkill from
      # procps, which left the image in the tier-1 diet (shutdown was broken)
      "runit/1".source = lib.mkForce (
        pkgs.writeScript "runit-1" ''
          #!${sh}
          echo fern > /proc/sys/kernel/hostname
          mkdir /bin/
          ln -s ${sh} /bin/sh
          touch /etc/runit/stopit
          chmod 0 /etc/runit/stopit
        ''
      );
      "runit/2".source = lib.mkForce (
        pkgs.writeScript "runit-2" ''
          #!${sh}
          cat /proc/uptime
          exec runsvdir -P /etc/service
        ''
      );
      "runit/3".source = lib.mkForce (
        pkgs.writeScript "runit-3" ''
          #!${sh}
          echo Waiting for services to stop...
          sv force-stop /etc/service/*
          sv exit /etc/service/*
          echo Unmounting filesystems, disabling swap...
          swapoff -a
          umount -r -a -t nosysfs,noproc,nodevtmpfs,notmpfs
          echo Remounting rootfs read-only...
          mount -o remount,ro /
          sync
          echo and down we go
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

  # /dev, /proc and /new are mount anchors for the initrd-free boot (see the
  # init= kernel param): the root fs is read-only, so the dirs must pre-exist
  # in the squashfs for fern-init to mount over them and pivot. fern-init
  # itself must be in the closure too: nothing in the toplevel references it.
  system.build.squashfs = lib.mkForce (
    pkgs.callPackage (pkgs.path + "/nixos/lib/make-squashfs.nix") {
      storeContents = [
        config.system.build.toplevel
        initScript
      ];
      pseudoFiles = [
        "/dev d 0755 0 0"
        "/proc d 0755 0 0"
        "/new d 0755 0 0"
      ];
    }
  );
}
