#!/usr/bin/env python3
"""List the images inside a PCI option ROM dump and check it belongs to the dGPU."""
import struct
import sys

WANT = (0x10DE, 0x25BC)  # NVIDIA RTX A1000 6GB Laptop GPU
CODE_TYPES = {0: "x86 BIOS (legacy)", 3: "EFI (GOP)"}

data = open(sys.argv[1], "rb").read()
print(f"{len(data)} bytes, first bytes: {data[:16].hex(' ')}")
if data.count(0xFF) == len(data) or data.count(0) == len(data):
    sys.exit("dump is blank (all 0xFF or 0x00): not a real vBIOS")

off, images, matches, has_efi = 0, 0, False, False
while off + 0x1A <= len(data):
    if data[off:off + 2] != b"\x55\xaa":
        if images == 0:
            print(f"no 55AA signature at 0x{off:x}")
        break
    pcir = off + struct.unpack_from("<H", data, off + 0x18)[0]
    if data[pcir:pcir + 4] != b"PCIR":
        print(f"image @0x{off:06x}: missing PCIR structure")
        break
    vendor, device = struct.unpack_from("<HH", data, pcir + 4)
    length = struct.unpack_from("<H", data, pcir + 0x10)[0] * 512
    code, indicator = data[pcir + 0x14], data[pcir + 0x15]
    kind = CODE_TYPES.get(code, f"code type 0x{code:02x}")
    print(f"image @0x{off:06x}: {vendor:04x}:{device:04x}  {length:>7} bytes  {kind}")
    images += 1
    matches |= (vendor, device) == WANT
    has_efi |= code == 3
    if indicator & 0x80 or length == 0:
        break
    off += length

print()
print("matches 10de:25bc:", "yes" if matches else "NO")
print("has UEFI GOP image:", "yes" if has_efi else "no (OVMF will not show boot output on this GPU)")
sys.exit(0 if matches else 1)
