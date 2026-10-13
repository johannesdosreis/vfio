#!/usr/bin/env bash
# Install the dynamic dGPU passthrough pieces. Run as root: sudo ./install-dynamic.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")

install -Dm755 "$here/vfio-dgpu" /usr/local/bin/vfio-dgpu
install -Dm755 "$here/libvirt-qemu-hook" /etc/libvirt/hooks/qemu
install -Dm644 "$here/vfio.conf" /etc/modprobe.d/vfio.conf
install -Dm644 "$here/61-dri-igpu.rules" /etc/udev/rules.d/61-dri-igpu.rules

# Create /dev/dri/igpu now with a "change" event on the Intel card only
# (an "add" event could make KWin pick up the NVIDIA card).
udevadm control --reload
for card in /sys/bus/pci/devices/0000:00:02.0/drm/card*; do
  udevadm trigger --action=change "$card"
done
udevadm settle

# libvirt only looks for hook scripts at startup; no VM is running.
systemctl restart libvirtd

echo "/dev/dri/igpu -> $(readlink -f /dev/dri/igpu)"
