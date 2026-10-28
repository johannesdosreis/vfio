#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Windows: bloquear
# @vicinae.mode silent
# @vicinae.icon 🔒
# @vicinae.keywords ["bloquear", "lock", "windows", "win11", "vm"]
# @vicinae.description Bloqueia a tela da VM win11 (ssh windows schtasks /Run /TN LockNow)

exec "$HOME/.local/bin/bloqueio" on
