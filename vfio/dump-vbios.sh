#!/usr/bin/env bash
# Dump the dGPU vBIOS through sysfs, plus the ACPI DSDT/SSDT tables (fallback source
# for laptops whose vBIOS lives behind the ACPI _ROM method).
# Run as root: sudo ./dump-vbios.sh
set -uo pipefail

dev=/sys/bus/pci/devices/0000:01:00.0
here=$(dirname "$(readlink -f "$0")")
out=$here/vbios-rtx-a1000.rom
acpi=$here/acpi
owner=${SUDO_USER:-root}

# ACPI tables: DSDT and SSDTs only (MSDM holds the Windows product key, skip it).
mkdir -p "$acpi"
cp /sys/firmware/acpi/tables/DSDT /sys/firmware/acpi/tables/SSDT* "$acpi"/
chown -R "$owner:" "$acpi"
echo "copied $(ls "$acpi" | wc -l) ACPI tables to $acpi"

echo 1 > "$dev/rom"
if cat "$dev/rom" > "$out"; then
  echo "wrote $(stat -c %s "$out") bytes to $out"
  chown "$owner:" "$out"
else
  echo "sysfs ROM read failed: GPU has no readable ROM BAR (vBIOS is probably in ACPI _ROM)" >&2
  rm -f "$out"
fi
echo 0 > "$dev/rom"
