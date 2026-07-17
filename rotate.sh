#!/usr/bin/env bash
# Change display rotation (matches LCD-show's rotate.sh invocation):
#   sudo ./rotate.sh [0|90|180|270]
# No reboot: the compositor transform rotates the output. Touch input is not
# re-mapped for the new rotation; only the default (90) is verified, see README.
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
