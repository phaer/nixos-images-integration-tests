#!/usr/bin/env bash

set -euo pipefail
set -x 
image_name="${1}"
efi_boot="${2:-}"

if which nom-build >/dev/null
then
    echo "using nom-build instead of nix-build"
    nix_build=nom-build
else
    nix_build=nix-build
fi


mkdir -p outputs
file_path="$(nix-instantiate --eval --json --expr "(import ./. {}).nixos.images.${image_name}.passthru.filePath"  | jq -r .)"
readable_image="outputs/${image_name}/${file_path}"


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

image_info() {
    cat <<EOF
# Image Info
path: $readable_image
size: $(du -h $readable_image | cut -f 1)
EOF
}

image_info $readable_image

echo "Copying $image_name to make it writable..."
install -m 0644 "$readable_image" "$writable_image"

if [ ! -z "$efi_boot" ]
then
    echo "preparing EFI boot"
    ovmf_firmware="$($nix_build . -A ovmf)/FV/OVMF_CODE.fd"
    efi_vars="${NIX_EFI_VARS:-nixos-efi-vars.fd}"
    test -f "$efi_vars" || truncate -s 4096 "$efi_vars"
    efi_boot="-drive if=pflash,format=raw,unit=0,readonly=on,file=${ovmf_firmware} \
    -drive if=pflash,format=raw,file=${efi_vars}"
fi

echo "starting qemu"
qemu-system-x86_64 \
    -machine type=q35,accel=kvm \
    -cpu host \
    -m 2048 \
    -device virtio-rng-pci \
    -device vhost-vsock-pci,guest-cid=3 \
    -net nic,netdev=user.0,model=virtio -netdev user,id=user.0,"${QEMU_NET_OPTS:-}" \
    -device virtio-keyboard \
    -usb \
    -nographic \
    -device usb-tablet,bus=usb-bus.0 \
    -chardev socket,id=char0,path=./monitor.sock,server=on,wait=off \
    -mon chardev=char0 \
    -chardev socket,id=char1,path=./serial.sock,server=on,wait=off \
    -serial chardev:char1 \
    $efi_boot \
    -drive "file=${writable_image}"

#timeout -f 2m bash -c 'until [ "$(ssh vsock/3 -o User=root  -i ~/src/nixpkgs/nixos/modules/profiles/keys/ssh_host_ed25519_key systemctl status | awk "/^\W*State:/ {print \$2}")" = "running" ]; do sleep 3; done'
#if [ $? -gt 123 ]
#then
#    echo >2 "could not reach vm!"
#    exit 1
#fi
#echo "could reach vm"
#
#if tty -s
#then
#   reptyr -T $qemu_pid
#else
#    kill $qemu_pid
#fi
