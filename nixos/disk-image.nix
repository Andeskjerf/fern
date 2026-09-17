{
  pkgs,
  kernel,
  initialRamdisk,
  squashfs,
  kernelParams,
}:
let
  syslinuxCfg = pkgs.writeText "syslinux.cfg" ''
    default fern
    timeout 1
    label fern
      kernel /bzImage
      append initrd=/initrd root=/dev/vda2 ${kernelParams}
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
        initialRamdisk
        squashfs
        kernelParams
        ;
    };
  }
  ''
    set -euo pipefail

    # boot partition: kernel + initrd + 4 MiB for FAT tables, ldlinux, cfg
    BOOT_BYTES=$(( $(stat -c%s ${kernel}/bzImage) + $(stat -c%s ${initialRamdisk}/initrd) + 4 * 1024 * 1024 ))
    BOOT_SECTORS=$(( (BOOT_BYTES + 511) / 512 ))
    BOOT_START=2048
    SQ_START=$(( BOOT_START + BOOT_SECTORS ))
    SQ_SECTORS=$(( ($(stat -c%s ${squashfs}) + 4095) / 4096 * 4096 / 512 ))
    truncate -s $(( (SQ_START + SQ_SECTORS) * 512 )) $out

    truncate -s $(( BOOT_SECTORS * 512 )) boot.vfat
    mkfs.vfat -F 16 -n BOOT boot.vfat
    mcopy -i boot.vfat ${kernel}/bzImage ::bzImage
    mcopy -i boot.vfat ${initialRamdisk}/initrd ::initrd
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
