#!/usr/bin/env bash
# Install the staged /etc/default/limine (zram/zswap fix + IOMMU) and regenerate boot entries.
# Run as root: sudo ./apply-limine.sh
# Roll back: sudo cp -a /etc/default/limine.bak-20261013 /etc/default/limine && sudo limine-update
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
backup=/etc/default/limine.bak-20261013

[[ -e $backup ]] || cp -a /etc/default/limine "$backup"
install -m 0644 -o root -g root "$here/limine.new" /etc/default/limine
diff -u "$backup" /etc/default/limine || true

limine-update

echo
echo "entries with intel_iommu=on: $(grep -c 'intel_iommu=on' /boot/limine.conf)"
grep -n -m4 'kernel_cmdline' /boot/limine.conf
