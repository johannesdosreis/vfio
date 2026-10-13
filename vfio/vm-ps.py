#!/usr/bin/env python3
"""Run a PowerShell script inside the win11 VM through the QEMU guest agent (runs as SYSTEM).

Usage: vm-ps.py 'Get-Process | Select -First 3'      (script as argument)
       vm-ps.py - < script.ps1                         (script on stdin)
Prints the guest's stdout/stderr and exits with the guest's exit code.
"""
import base64
import json
import subprocess
import sys
import time

VM = "win11"
TIMEOUT_S = 1800


def agent(cmd, **args):
    out = subprocess.run(
        ["virsh", "-c", "qemu:///system", "qemu-agent-command", VM, "--timeout", "30",
         json.dumps({"execute": cmd, "arguments": args})],
        check=True, capture_output=True, text=True).stdout
    return json.loads(out)["return"]


script = sys.stdin.read() if sys.argv[1:] == ["-"] else " ".join(sys.argv[1:])
# UTF-16LE base64 so quoting and accents survive the trip
encoded = base64.b64encode(
    ("$ProgressPreference='SilentlyContinue'\n"
     "[Console]::OutputEncoding=[Text.Encoding]::UTF8\n" + script).encode("utf-16-le")).decode()
pid = agent("guest-exec", path="powershell.exe",
            arg=["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
            **{"capture-output": True})["pid"]

deadline = time.time() + TIMEOUT_S
while True:
    status = agent("guest-exec-status", pid=pid)
    if status.get("exited"):
        break
    if time.time() > deadline:
        sys.exit(f"timed out after {TIMEOUT_S}s (guest pid {pid} still running)")
    time.sleep(1)

for key, stream in (("out-data", sys.stdout), ("err-data", sys.stderr)):
    if key in status:
        stream.write(base64.b64decode(status[key]).decode("utf-8", "replace"))
sys.exit(status.get("exitcode", 0))
