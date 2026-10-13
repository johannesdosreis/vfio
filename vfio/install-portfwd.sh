#!/usr/bin/env bash
# Install the Sunshine port forwarding for the win11 VM and apply it now if the VM is running.
# Run as root: sudo ./install-portfwd.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
install -Dm755 "$here/win11-portfwd" /usr/local/bin/win11-portfwd
install -Dm755 "$here/libvirt-qemu-hook" /etc/libvirt/hooks/qemu
iptables -L LIBVIRT_FWI -n >/dev/null # libvirt's chain must exist (iptables firewall backend)
if [[ $(LC_ALL=C virsh -c qemu:///system domstate win11) == running ]]; then
  win11-portfwd add
fi
win11-portfwd status
