#!/usr/bin/env bash
# Check the new kernel cmdline took effect: IOMMU passthrough mode, zram off, zswap on lz4.
# Run as your normal user after rebooting into each kernel (linux-cachyos and -lts).

check() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fi; }

echo "kernel: $(uname -r)"
check "cmdline has intel_iommu=on iommu=pt" "grep -q 'intel_iommu=on iommu=pt' /proc/cmdline"
check "cmdline has systemd.zram=0" "grep -q 'systemd.zram=0' /proc/cmdline"
check "no zram swap" "! grep -q zram /proc/swaps"
check "swapfile active" "grep -q /swap/swapfile /proc/swaps"
check "zswap enabled" "grep -qx Y /sys/module/zswap/parameters/enabled"
check "zswap compressor is lz4" "grep -qx lz4 /sys/module/zswap/parameters/compressor"
check "zswap pool is 30%" "grep -qx 30 /sys/module/zswap/parameters/max_pool_percent"
check "dGPU alone in its IOMMU group" "[ \$(ls /sys/bus/pci/devices/0000:01:00.0/iommu_group/devices | wc -l) -eq 1 ]"

echo
echo "dGPU IOMMU group: $(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/iommu_group)")"
echo "iommu groups total: $(ls /sys/kernel/iommu_groups | wc -l)"
swapon --show

echo
igpu=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-card)
check "iGPU has the first render node (renderD128)" "[ \"\$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-render)\" = /dev/dri/renderD128 ]"
check "/dev/dri/igpu points to the Intel card" "[ \"\$(readlink -f /dev/dri/igpu)\" = $igpu ]"
check "KWin pinned (KWIN_DRM_DEVICES)" "systemctl --user show-environment | grep -qx KWIN_DRM_DEVICES=/dev/dri/igpu"
nv_nodes=$(ls /sys/bus/pci/devices/0000:01:00.0/drm 2>/dev/null | sed 's|^|/dev/dri/|' | paste -sd'|')
kwin=$(pgrep -x kwin_wayland)
if ls "/proc/$kwin/fd" >/dev/null 2>&1; then
  check "KWin not holding the dGPU" "! ls -l /proc/$kwin/fd | grep -E ' -> (${nv_nodes:-none})\$' >/dev/null"
else
  echo "skip KWin not holding the dGPU (kwin's fds need root: sudo ./vfio/test-dynamic.sh)"
fi
