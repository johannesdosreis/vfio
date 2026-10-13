#!/usr/bin/env bash
# Show whether Moonlight's connection attempts reach the host and get forwarded to the VM.
# Run as root: sudo ./diag-portfwd.sh   (retry the connection in Moonlight during the 45 s window)
set -uo pipefail

counters() {
  echo "-- DNAT (nat PREROUTING)"
  iptables -t nat -L PREROUTING -v -n -x | grep -E '192\.168\.122\.144'
  echo "-- forward accept (LIBVIRT_FWI)"
  iptables -L LIBVIRT_FWI -v -n -x | grep -E 'ctstate DNAT|REJECT'
}

echo "== ufw"; ufw status verbose | head -12
echo; echo "== FORWARD chain order"; iptables -L FORWARD -n --line-numbers | head -8
echo; echo "== before"; counters
echo; echo ">>> agora tente conectar no Moonlight (45 s)..."; sleep 45
echo; echo "== after"; counters
