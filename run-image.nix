{
  writeShellScriptBin,
  qemu,
  kernel,
  squashfs,
  kernelParams,
}:

writeShellScriptBin "fern-image-qemu" ''
  exec ${qemu}/bin/qemu-system-x86_64 \
    -m 512 \
    -enable-kvm \
    -cpu host \
    -kernel ${kernel}/bzImage \
    -drive file=${squashfs},readonly=on,media=cdrom,format=raw,if=virtio \
    -append "console=ttyS0 ${kernelParams} root=/dev/vda" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -nographic -no-reboot
''
