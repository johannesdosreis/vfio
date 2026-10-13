#!/usr/bin/env bash
# Create the Windows 11 VM: images subvolume, disk, fake-battery ACPI table, libvirt domain.
# Run as root: sudo ./setup-vm.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
images=/var/lib/libvirt/images
disk=$images/win11.qcow2
disk_size=100G
acpi_dir=/var/lib/libvirt/acpi
virtio_iso=/home/johannes/Downloads/virtio-win-0.1.302.iso

# VM images in their own btrfs subvolume: snapper snapshots of @ skip nested subvolumes,
# so a growing VM disk does not get pinned by every snapshot. No CoW for the image.
if [[ $(stat -c %i "$images") != 256 ]]; then
  if [[ -n $(ls -A "$images") ]]; then
    echo "$images is not empty; move its contents out first" >&2
    exit 1
  fi
  mode=$(stat -c %a "$images")
  owner=$(stat -c %u:%g "$images")
  rmdir "$images"
  btrfs subvolume create "$images"
  chattr +C "$images"
  chmod "$mode" "$images"
  chown "$owner" "$images"
  virsh -c qemu:///system pool-refresh default >/dev/null
fi
echo "images: $(stat -c 'inode %i' "$images"), attrs $(lsattr -d "$images" | cut -d' ' -f1)"

if [[ ! -e $disk ]]; then
  qemu-img create -f qcow2 -o preallocation=metadata "$disk" "$disk_size"
fi

# Fake battery SSDT (iasl comes from acpica)
pacman -S --needed --noconfirm acpica
install -d -m 0755 "$acpi_dir"
iasl -p "$acpi_dir/ssdt-battery" "$here/ssdt-battery.asl"
chmod 0644 "$acpi_dir/ssdt-battery.aml"

[[ -e $virtio_iso ]] || echo "WARNING: $virtio_iso missing; the VM will not start until it exists"

virsh -c qemu:///system define "$here/win11.xml"
virsh -c qemu:///system dominfo win11 | grep -E '^(Nome|Name|Estado|State|CPU|Mem)'
