#!/usr/bin/env bash
# Round-trip the dGPU nvidia -> vfio-pci -> nvidia twice without a VM. The second round
# also proves KWin did not grab the dGPU when it came back (detach would refuse). Run as root.
set -uo pipefail

kwin_dri() {
  echo "KWin DRM nodes:"
  ls -l "/proc/$(pgrep -x kwin_wayland)/fd" | grep -oE '/dev/dri/[a-zA-Z0-9]+' | sort | uniq -c
}

echo "iGPU: $(readlink -f /dev/dri/igpu)   dGPU: $(ls /sys/bus/pci/devices/0000:01:00.0/drm | sed 's|^|/dev/dri/|' | paste -sd' ')"
kwin_dri
vfio-dgpu status

for round in 1 2; do
  echo
  echo "== round $round: detach"
  vfio-dgpu detach || exit 1
  lspci -nnk -s 01:00.0 | grep 'driver in use'
  echo "== round $round: attach"
  vfio-dgpu attach || exit 1
  sleep 3
done

echo
vfio-dgpu status
kwin_dri
for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
  [[ -d /sys/module/$m ]] && echo "ok   $m loaded" || echo "FAIL $m not loaded"
done
