#!/usr/bin/env bash
# Install the i915-before-nvidia rule and rebuild the initramfs (the modconf hook copies
# /etc/modprobe.d into it). Run as root: sudo ./install-igpu-first.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")

install -Dm644 "$here/igpu-first.conf" /etc/modprobe.d/igpu-first.conf
modprobe -c | grep -E '^install nvidia'
limine-update
echo
# limine-mkinitcpio-hook layout: /boot/<machine-id>/<kernel>/initramfs
for img in /boot/*/linux-*/initramfs; do
  printf '%s: ' "$img"
  lsinitcpio "$img" | grep -q 'etc/modprobe.d/igpu-first.conf' && echo "has igpu-first.conf" || echo "MISSING igpu-first.conf"
done
