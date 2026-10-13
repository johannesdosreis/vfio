#!/usr/bin/env bash
# Build the AUR looking-glass pkgbase (B7) and install only looking-glass-module-dkms (kvmfr).
# Run as your user (makepkg refuses root); it calls sudo for the pacman steps.
set -euo pipefail
src=${1:?usage: build-kvmfr.sh <path to AUR looking-glass clone>}
cd "$src"

sudo pacman -S --needed --asdeps --noconfirm wayland-protocols   # build-only dependency
makepkg -f --noconfirm                                            # client + module + obs plugin
pkg=$(ls looking-glass-module-dkms-*.pkg.tar.zst)
sudo pacman -U --noconfirm "$pkg"                                 # pulls dkms; its hook builds kvmfr per kernel

echo
dkms status looking-glass
