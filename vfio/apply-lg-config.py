#!/usr/bin/env python3
"""Switch the win11 VM from install mode (VGA + USB tablet) to Looking Glass mode.

Edits libvirt's current inactive definition (keeps UUID, MAC, NVRAM, PCI addresses):
  - video model none: Windows renders only on the NVIDIA (virtual display), Looking Glass shows it
  - drop the USB tablet (absolute pointer fights Looking Glass' relative mouse)
  - virtio mouse + keyboard for Looking Glass/SPICE input
  - QEMU guest agent channel
Usage: apply-lg-config.py [--apply]   (default: print the diff only; --apply needs the VM shut off)
"""
import difflib
import subprocess
import sys
import xml.etree.ElementTree as ET

VM = "win11"
VIRSH = ["virsh", "-c", "qemu:///system"]


def virsh(*args, **kw):
    return subprocess.run(VIRSH + list(args), check=True, capture_output=True, text=True, **kw).stdout


ET.register_namespace("qemu", "http://libvirt.org/schemas/domain/qemu/1.0")
before = virsh("dumpxml", "--inactive", "--security-info", VM)
root = ET.fromstring(before)
devices = root.find("devices")

for video in devices.findall("video"):
    model = video.find("model")
    model.attrib.clear()
    model.set("type", "none")
    for child in list(video):
        if child.tag != "model":
            video.remove(child)

for inp in devices.findall("input"):
    if inp.get("type") == "tablet":
        devices.remove(inp)

existing = {(i.get("type"), i.get("bus")) for i in devices.findall("input")}
for kind in ("mouse", "keyboard"):
    if (kind, "virtio") not in existing:
        devices.append(ET.Element("input", {"type": kind, "bus": "virtio"}))

if not any(t.get("name") == "org.qemu.guest_agent.0" for t in devices.iter("target")):
    channel = ET.SubElement(devices, "channel", {"type": "unix"})
    ET.SubElement(channel, "target", {"type": "virtio", "name": "org.qemu.guest_agent.0"})

def serialize(elem):
    ET.indent(elem)
    return ET.tostring(elem, encoding="unicode") + "\n"


after = serialize(root)
# diff against the original run through the same serializer, so only real changes show
sys.stdout.writelines(difflib.unified_diff(serialize(ET.fromstring(before)).splitlines(True),
                                           after.splitlines(True), "current", "looking-glass"))

if "--apply" in sys.argv:
    state = virsh("domstate", VM).strip()
    if state not in ("shut off", "desligado"):
        sys.exit(f"{VM} is '{state}': shut Windows down first")
    subprocess.run(VIRSH + ["define", "/dev/stdin"], input=after, check=True, text=True)
