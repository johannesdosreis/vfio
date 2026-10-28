#!/usr/bin/env python3
"""Exercise follower services without touching the real GPU or systemd."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
GATEWAY = "hermes-gateway.service"
SUNSHINE = "app-dev.lizardbyte.app.Sunshine.service"


class FollowUnitsTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(os.environ.get("TMPDIR", Path.home() / ".hermes/cache/scratch"))
        self.temp = tempfile.TemporaryDirectory(prefix="vfio-test-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dev = self.root / "pci/devices/0000:01:00.0"
        (self.dev / "driver").mkdir(parents=True)
        self.proc = self.root / "proc"
        self.proc.mkdir()
        self.calls = self.root / "calls"
        self.busy = self.root / "busy"
        self.busy.write_text("")

    def run_bash(self, script):
        return subprocess.run(
            ["bash", "-c", script],
            env={**os.environ, "TEST_ROOT": str(self.root)},
            text=True,
            capture_output=True,
            timeout=10,
        )

    def run_hook(self, action, *, busy=False, active=True, failed=False, unload_fails=False):
        source = (HERE / "vfio-dgpu").read_text()
        definitions, guard, _ = source.partition("\nif [[ $EUID -ne 0 ]]; then")
        self.assertTrue(guard, "test must load definitions, not execute the real hook")
        definitions = definitions.replace("/sys/bus/pci", str(self.root / "pci"))
        self.busy.write_text("4242 hermes\n" if busy else "")
        script = definitions + f'''
STATE="$TEST_ROOT/state"
driver_name=nvidia
active={int(active)}
failed={int(failed)}
unload_fails={int(unload_fails)}
driver() {{ printf '%s\\n' "$driver_name"; }}
log() {{ :; }}
holders() {{ cat "$TEST_ROOT/busy"; }}
flatpak_pids() {{ :; }}
systemctl() {{
  [[ $1 == show ]] && printf '0\\n'
  return 0
}}
user_systemctl() {{
  printf '%s\\n' "$*" >>"$TEST_ROOT/calls"
  case $1 in
    show) [[ ${{!#}} == {GATEWAY} ]] && printf '4242\\n' || printf '0\\n' ;;
    stop) : >"$TEST_ROOT/busy" ;;
    is-active) [[ ${{!#}} == {GATEWAY} && $active == 1 ]] ;;
    is-failed) [[ ${{!#}} == {GATEWAY} && $failed == 1 ]] ;;
    *) return 0 ;;
  esac
}}
modprobe() {{
  if [[ $1 == -r ]]; then
    ((unload_fails)) && return 1
    driver_name=none
  elif [[ $1 == vfio-pci ]]; then
    driver_name=vfio-pci
  elif [[ $1 == -a ]]; then
    driver_name=nvidia
  fi
  return 0
}}
{action}
'''
        result = self.run_bash(script)
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return result, calls

    def test_detach_stops_and_restarts_gateway_holding_nvidia(self):
        result, calls = self.run_hook("detach", busy=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"stop {GATEWAY}", calls)
        self.assertIn(f"reset-failed {GATEWAY}", calls)
        self.assertIn(f"restart {GATEWAY}", calls)
        self.assertLess(calls.index(f"stop {GATEWAY}"), calls.index(f"restart {GATEWAY}"))
        self.assertNotIn(f"stop {SUNSHINE}", calls)
        self.assertEqual((self.dev / "driver_override").read_text().strip(), "vfio-pci")
        self.assertEqual((self.root / "state/user").read_text(), "")

    def test_detach_leaves_gateway_alone_when_not_holding_nvidia(self):
        result, calls = self.run_hook("detach")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(f"stop {GATEWAY}", calls)
        self.assertNotIn(f"restart {GATEWAY}", calls)

    def test_detach_failure_restores_gateway(self):
        result, calls = self.run_hook("detach", busy=True, unload_fails=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(f"stop {GATEWAY}", calls)
        self.assertIn(f"restart {GATEWAY}", calls)
        self.assertFalse((self.root / "state").exists())

    def test_attach_restarts_active_or_failed_gateway_but_not_inactive(self):
        for active, failed in ((True, False), (False, True), (False, False)):
            with self.subTest(active=active, failed=failed):
                self.calls.unlink(missing_ok=True)
                result, calls = self.run_hook("attach", active=active, failed=failed)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(f"restart {GATEWAY}" in calls, active or failed)

    def test_sunshine_remains_a_follower(self):
        source = (HERE / "vfio-dgpu").read_text().partition("\nif [[ $EUID -ne 0 ]]; then")[0]
        result = self.run_bash(source + '\nprintf "%s\\n" "${FOLLOW_UNITS[@]}"\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(SUNSHINE, result.stdout.splitlines())

    def run_diagnostic(self, comm, gateway_pid=0):
        process = self.proc / "4242"
        (process / "fd").mkdir(parents=True, exist_ok=True)
        (process / "fd/3").unlink(missing_ok=True)
        (process / "fd/3").symlink_to("/dev/nvidia0")
        (process / "comm").write_text(comm + "\n")

        if (self.dev / "driver").is_symlink():
            (self.dev / "driver").unlink()
        else:
            (self.dev / "driver").rmdir()
        (self.dev / "driver").symlink_to("/drivers/nvidia")
        source = (HERE / "home/.local/bin/nvidia-users").read_text()
        source = source.replace("/proc/", str(self.proc) + "/")
        source = source.replace("/sys/bus/pci", str(self.root / "pci"))
        return self.run_bash(
            "ps() { printf 'test-process\\n'; }\n"
            "find() { printf '/proc/4242/fd/3\\n'; }\n"
            f"systemctl() {{ printf '{gateway_pid}\\n'; }}\n" + source
        )

    def test_diagnostic_recognizes_gateway_main_pid_with_any_comm(self):
        for comm in ("hermes", "python3"):
            with self.subTest(comm=comm):
                result = self.run_diagnostic(comm, gateway_pid=4242)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("  ok      ", result.stdout)
                self.assertNotIn("  FECHAR  ", result.stdout)

    def test_diagnostic_does_not_exempt_unmanaged_hermes(self):
        result = self.run_diagnostic("hermes")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("  FECHAR  ", result.stdout)

    def test_diagnostic_keeps_sunshine_handled(self):
        result = self.run_diagnostic("sunshine")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("  ok      ", result.stdout)


if __name__ == "__main__":
    unittest.main()
