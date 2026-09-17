{
  pkgs,
  kernel,
  squashfs,
  kernelParams,
}:
let
  syslinuxCfg = pkgs.writeText "syslinux.cfg" ''
    default fern
    timeout 1
    label fern
      kernel /bzImage
      append root=/dev/vda2 ${kernelParams}
  '';
in
pkgs.runCommand "fern-image"
  {
    nativeBuildInputs = with pkgs; [
      dosfstools
      mtools
      syslinux
      util-linux
    ];
    passthru = {
      inherit
        kernel
        squashfs
        kernelParams
        ;
    };
  }
  ''
    set -euo pipefail

    # boot partition: kernel + 4 MiB for FAT tables, ldlinux, cfg (no initrd:
    # the kernel mounts the squashfs root itself, see fern-init)
    BOOT_BYTES=$(( $(stat -c%s ${kernel}/bzImage) + 4 * 1024 * 1024 ))
    BOOT_SECTORS=$(( (BOOT_BYTES + 511) / 512 ))
    BOOT_START=2048
    SQ_START=$(( BOOT_START + BOOT_SECTORS ))
    SQ_SECTORS=$(( ($(stat -c%s ${squashfs}) + 4095) / 4096 * 4096 / 512 ))
    truncate -s $(( (SQ_START + SQ_SECTORS) * 512 )) $out

    truncate -s $(( BOOT_SECTORS * 512 )) boot.vfat
    # -s 1: with the pruned kernel the volume is too small for dosfstools'
    # auto cluster size (4-sector clusters → under FAT16's 4085-cluster floor)
    mkfs.vfat -F 16 -s 1 -n BOOT boot.vfat
    mcopy -i boot.vfat ${kernel}/bzImage ::bzImage
    mcopy -i boot.vfat ${syslinuxCfg} ::syslinux.cfg
    ${pkgs.syslinux}/bin/syslinux boot.vfat

    dd if=boot.vfat of=$out bs=512 seek=$BOOT_START conv=notrunc
    dd if=${squashfs} of=$out bs=512 seek=$SQ_START conv=notrunc
    dd if=${pkgs.syslinux}/share/syslinux/mbr.bin of=$out bs=440 count=1 conv=notrunc
    sfdisk $out <<EOF
    label: dos
    unit: sectors
    $BOOT_START,$BOOT_SECTORS,0e,*
    $SQ_START,$SQ_SECTORS,83
    EOF
  ''
