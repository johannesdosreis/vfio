#!/usr/bin/env python3
"""Copy host files into the win11 VM through the QEMU guest agent.

Usage: vm-put.py <guest-dir> <file>...     e.g. vm-put.py 'C:\\vfio-setup\\ivshmem' ivshmem.inf ivshmem.sys
The guest directory must already exist.
"""
import base64
import json
import os
import subprocess
import sys

VM = "win11"
CHUNK = 48 * 1024  # bytes per guest-file-write; keeps each virsh call small


def agent(cmd, **args):
    out = subprocess.run(
        ["virsh", "-c", "qemu:///system", "qemu-agent-command", VM, "--timeout", "30",
         json.dumps({"execute": cmd, "arguments": args})],
        check=True, capture_output=True, text=True).stdout
    return json.loads(out)["return"]


guest_dir, files = sys.argv[1].rstrip("\\"), sys.argv[2:]
for path in files:
    target = f"{guest_dir}\\{os.path.basename(path)}"
    handle = agent("guest-file-open", path=target, mode="wb")
    try:
        with open(path, "rb") as f:
            while chunk := f.read(CHUNK):
                agent("guest-file-write", handle=handle, **{"buf-b64": base64.b64encode(chunk).decode()})
    finally:
        agent("guest-file-close", handle=handle)
    print(f"{target}  {os.path.getsize(path)} bytes")
