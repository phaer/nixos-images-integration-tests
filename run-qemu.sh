#!/usr/bin/env bash

set -euxo pipefail

image_name="${1}"

if which nom-build >/dev/null
then
    echo "using nom-build instead of nix-build"
    nix_build=nom-build
else
    nix_build=nix-build
fi


file_path="$(nix-instantiate --eval --json --expr "(import ./. {}).nixos.images.${image_name}.passthru.filePath"  | jq -r .)"
ovmf_firmware="$($nix_build . -A ovmf)/FV/OVMF_CODE.fd"
efi_vars="${NIX_EFI_VARS:-nixos-efi-vars.fd}"
readable_image="outputs/${image_name}/${file_path}"

mkdir -p outputs
test -f "$efi_vars" || truncate -s 4096 "$efi_vars"

if [ -f "$readable_image" ]
then
    echo "$readable_image found"
else
    echo "$readable_image not found, building $image_name..."
    $nix_build -A "images.${image_name}" --out-link "outputs/${image_name}"
fi


writable_image=$(mktemp) || {
  echo "Failed to create writable_image file" >&2
  exit 1
}

# Cleanup function to remove the temp file
cleanup() {
  echo "Cleaning up..."
  rm -f "$writable_image"
}

# Trap EXIT (script ending), INT (Ctrl+C), TERM (kill), and ERR (error in script)
trap cleanup EXIT INT TERM ERR

echo "Copying $image_name to make it writable..."
install -m 0644 "$readable_image" "$writable_image"

qemu-system-x86_64 \
    -machine type=q35,accel=kvm \
    -cpu host \
    -m 2048 \
    -device virtio-rng-pci \
    -net nic,netdev=user.0,model=virtio -netdev user,id=user.0,"${QEMU_NET_OPTS:-}" \
    -device virtio-keyboard \
    -usb \
    -device usb-tablet,bus=usb-bus.0 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${ovmf_firmware}" \
    -drive "if=pflash,format=raw,file=${efi_vars}" \
    -drive "file=${writable_image}"

