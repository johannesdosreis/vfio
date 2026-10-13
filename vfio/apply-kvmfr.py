#!/usr/bin/env python3
"""Switch the win11 VM's Looking Glass buffer from /dev/shm (libvirt <shmem>) to /dev/kvmfr0.

kvmfr lets the client import frames as DMA-BUF straight into the GPU instead of copying them.
libvirt has no element for a kvmfr-backed ivshmem device, so it goes in as QEMU arguments
(as in the Looking Glass B7 docs); /dev/kvmfr0 must be in qemu.conf's cgroup_device_acl.
Usage: apply-kvmfr.py [--apply]   (default: print the diff only; --apply needs the VM shut off)
"""
import difflib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

VM = "win11"
QEMU_NS = "http://libvirt.org/schemas/domain/qemu/1.0"
SIZE = 32 * 1024 * 1024  # must match options kvmfr static_size_mb=32
ARGS = [
    "-device", json.dumps({"driver": "ivshmem-plain", "id": "shmem0", "memdev": "looking-glass"}),
    "-object", json.dumps({"qom-type": "memory-backend-file", "id": "looking-glass",
                           "mem-path": "/dev/kvmfr0", "size": SIZE, "share": True}),
]


def virsh(*args, **kw):
    return subprocess.run(["virsh", "-c", "qemu:///system", *args],
                          check=True, capture_output=True, text=True, **kw).stdout


def serialize(elem):
    ET.indent(elem)
    return ET.tostring(elem, encoding="unicode") + "\n"


ET.register_namespace("qemu", QEMU_NS)
before = virsh("dumpxml", "--inactive", "--security-info", VM)
root = ET.fromstring(before)
devices = root.find("devices")

for shmem in devices.findall("shmem"):
    if shmem.get("name") == "looking-glass":
        devices.remove(shmem)

cmdline = root.find(f"{{{QEMU_NS}}}commandline")
if cmdline is None:
    cmdline = ET.SubElement(root, f"{{{QEMU_NS}}}commandline")
if not any("/dev/kvmfr0" in (a.get("value") or "") for a in cmdline):
    for value in ARGS:
        ET.SubElement(cmdline, f"{{{QEMU_NS}}}arg", {"value": value})

after = serialize(root)
sys.stdout.writelines(difflib.unified_diff(serialize(ET.fromstring(before)).splitlines(True),
                                           after.splitlines(True), "current", "kvmfr"))

if "--apply" in sys.argv:
    state = virsh("domstate", VM).strip()
    if state not in ("shut off", "desligado"):
        sys.exit(f"{VM} is '{state}': shut Windows down first")
    subprocess.run(["virsh", "-c", "qemu:///system", "define", "/dev/stdin"], input=after, check=True, text=True)
