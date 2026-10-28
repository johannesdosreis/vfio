#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Windows: desbloquear
# @vicinae.mode silent
# @vicinae.icon 🔓
# @vicinae.keywords ["desbloquear", "unlock", "windows", "win11", "vm"]
# @vicinae.description Desbloqueia a tela da VM win11 sem senha (ssh windows schtasks /Run /TN UnlockNow)

exec "$HOME/.local/bin/bloqueio" off
