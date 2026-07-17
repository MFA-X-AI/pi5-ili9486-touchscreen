#!/usr/bin/env bash
# Orchestrator for a fresh Pi. Safe to re-run at any point; it detects where
# you are in the process and continues from there.
#
#   Run 1:  installs the piscreen,drm overlay  -> asks you to reboot
#   Run 2:  verifies the stack, then calibrates (or uses defaults) and persists
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.env
source "$SCRIPT_DIR/defaults.env"

require_root

# If the panel is not yet a connected DRM output, this is run 1.
if ! grep -q '^connected$' /sys/class/drm/card*-"$OUTPUT_NAME"/status 2>/dev/null; then
  log "Panel not detected as DRM output $OUTPUT_NAME — installing overlay (step 1)."
  "$SCRIPT_DIR/steps/01-enable-display.sh"
  echo
  warn "Reboot now (sudo reboot), then run sudo ./setup.sh again to continue."
  exit 0
fi

log "Panel already registered as $OUTPUT_NAME — verifying (step 2)."
"$SCRIPT_DIR/steps/02-verify-boot.sh"

echo
printf 'Calibrate touch interactively now? (recommended; N uses the known-good default matrix) [Y/n] '
read -r ans
if [ "${ans,,}" != "n" ]; then
  "$SCRIPT_DIR/steps/03-calibrate-touch.sh"
  "$SCRIPT_DIR/steps/04-persist.sh"
else
  "$SCRIPT_DIR/steps/04-persist.sh" --use-defaults
fi

echo
log "Setup complete. Log out/in (or reboot) to apply rotation and scale."
log "Diagnostics: ./doctor.sh"
