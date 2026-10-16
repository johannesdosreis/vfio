#!/usr/bin/env bash
# Check that Sunshine and waywallen follow the dGPU: detach, wait like a running VM would,
# show which GPU each one picked, then attach and show again. Run as root.
set -uo pipefail

report() {
  echo "-- Sunshine (last start)"
  journalctl _SYSTEMD_USER_UNIT=app-dev.lizardbyte.app.Sunshine.service --since "-25s" -o cat --no-pager |
    grep -E "config: 'encoder'|Found (H.264|HEVC) encoder|Encoder \[[a-z]+\] failed|Couldn't find any working" |
    sed 's/^\[[^]]*\]: //' | sort -u
  echo "-- waywallen renderer"
  local p
  for p in $(grep -l 'app-flatpak-org.waywallen.waywallen-' /proc/[0-9]*/cgroup 2>/dev/null | cut -d/ -f3); do
    [[ $(cat "/proc/$p/comm" 2>/dev/null) == waywallen-video ]] || continue
    ls -l "/proc/$p/fd" | grep -oE '/dev/(nvidia[a-z0-9-]*|dri/[a-zA-Z0-9]+)' | sort | uniq -c | tr -s ' \n' ' '
    echo
  done
}

vfio-dgpu detach || exit 1
sleep 20
echo "== GPU with the VM (vfio-pci); intel render node: $(readlink -f /dev/dri/by-path/pci-0000:00:02.0-render)"
report
echo
vfio-dgpu attach
sleep 20
echo "== GPU back on the host; nvidia render node: $(readlink -f /dev/dri/by-path/pci-0000:01:00.0-render)"
report
