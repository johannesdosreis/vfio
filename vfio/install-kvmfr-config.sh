#!/usr/bin/env bash
# Configure the kvmfr module (Looking Glass) and let libvirt VMs use /dev/kvmfr0.
# Run as root: sudo ./install-kvmfr-config.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")

install -Dm644 "$here/kvmfr.modprobe.conf" /etc/modprobe.d/kvmfr.conf
install -Dm644 "$here/kvmfr.modules-load.conf" /etc/modules-load.d/kvmfr.conf
install -Dm644 "$here/99-kvmfr.rules" /etc/udev/rules.d/99-kvmfr.rules
rm -f /etc/tmpfiles.d/10-looking-glass.conf # the /dev/shm buffer is no longer used

# libvirt confines VMs to a device allow-list: libvirt's default list plus /dev/kvmfr0
conf=/etc/libvirt/qemu.conf
if ! grep -qE '^\s*cgroup_device_acl' "$conf"; then
  cp -a "$conf" "$conf.bak-20261013"
  cat >>"$conf" <<'ACL'

# Looking Glass: kvmfr shared memory device (added 2026-10-13)
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/userfaultfd",
    "/dev/kvmfr0"
]
ACL
fi

udevadm control --reload
modprobe kvmfr
udevadm settle
systemctl restart libvirtd # running VMs keep running; libvirtd reconnects to them

ls -l /dev/kvmfr0
grep -A6 '^cgroup_device_acl' "$conf"
