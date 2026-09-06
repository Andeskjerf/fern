{
  writeShellScriptBin,
  qemu,
  image,
  OVMF,
}:

writeShellScriptBin "repart-image-qemu" ''
  set -euo pipefail

  mkdir -p images
  BASE_IMAGE="base.qcow2"
  DISK_IMAGE="images/worker-overlay.qcow2"

  if [[ ! -f "images/$BASE_IMAGE" ]]; then
    ${qemu}/bin/qemu-img convert -f raw \
      -O qcow2 -c ${image}/image.raw "images/$BASE_IMAGE"
      ${qemu}/bin/qemu-img resize -f qcow2 "images/$BASE_IMAGE" "+10G"
  fi

  if [[ -f "$DISK_IMAGE" ]]; then
    rm "$DISK_IMAGE"
  fi

  ${qemu}/bin/qemu-img create -f qcow2 \
    -b "$BASE_IMAGE" -F qcow2 "$DISK_IMAGE"
    ${qemu}/bin/qemu-img resize -f qcow2 "$DISK_IMAGE" "+10G"

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
