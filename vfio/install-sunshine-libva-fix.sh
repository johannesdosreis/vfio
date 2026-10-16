#!/usr/bin/env bash
# Work around CachyOS sunshine 2026.1015: its statically linked libva looks for VA-API drivers in
# the CI build directory, and because /usr/bin/sunshine has file capabilities (secure execution),
# libva ignores LIBVA_DRIVERS_PATH. Point that directory at the system drivers, then install the
# current vfio-dgpu. Remove /home/runner once the package is fixed.
# Run as root: sudo ./install-sunshine-libva-fix.sh
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
ci=/home/runner/work/build-deps/build-deps/build/libva/lib

install -d -m 0755 "$ci"
ln -sfn /usr/lib/dri "$ci/dri"
ls -l "$ci/dri"
ls "$ci/dri/" | grep -E '^(iHD|i965)_drv_video\.so$'

install -m755 "$here/vfio-dgpu" /usr/local/bin/vfio-dgpu
echo "vfio-dgpu installed"
