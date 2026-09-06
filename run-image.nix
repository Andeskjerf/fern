{
  writeShellScriptBin,
  qemu,
  image,
  OVMF,
}:

writeShellScriptBin "repart-image-qemu" ''
  set -euo pipefail

  mkdir -p images
  DISK_IMAGE="images/worker-overlay.qcow2"

  if [[ ! -f "$DISK_IMAGE" ]]; then
    ${qemu}/bin/qemu-img create -f qcow2 \
      -b ${image}/image.raw -F raw $DISK_IMAGE
      ${qemu}/bin/qemu-img resize -f qcow2 "$DISK_IMAGE" "+10G"
  fi

  ${qemu}/bin/qemu-system-x86_64 \
    -smp 4 \
    -m 2048 \
    --enable-kvm \
    -cpu host \
    -bios "${OVMF.fd}/FV/OVMF.fd" \
    -drive file="$DISK_IMAGE",format=qcow2,if=virtio \
    -serial stdio \
    -display gtk
''
