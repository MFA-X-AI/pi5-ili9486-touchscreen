#!/usr/bin/env bash
# Change display rotation (matches LCD-show's rotate.sh invocation):
#   sudo ./rotate.sh [0|90|180|270]
# Log out/in to apply: the compositor transform rotates the output. labwc applies
# the same transform to touch input, so a calibration made with
# steps/03-calibrate-touch.sh should stay valid; only the default (90) is verified
# on hardware, see README.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

rot="${1:-}"
case "$rot" in
  0|90|180|270) ;;
  *) die "Usage: sudo ./rotate.sh [0|90|180|270]" ;;
esac

# Same mapping as MHS35-show: LCD-show's '90' == our known-good transform 270.
export OUTPUT_TRANSFORM_OVERRIDE=$(( (270 + rot - 90 + 360) % 360 ))

"$SCRIPT_DIR/steps/04-persist.sh"
log "Rotation set to $rot. Log out/in (or reboot) to apply."
