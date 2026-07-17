#!/usr/bin/env bash
# Step 1: register the panel as a native DRM output via the piscreen overlay.
# No fbcp, no fbtft, no X11 — the panel becomes a second monitor under Wayland.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../defaults.env
source "$SCRIPT_DIR/../defaults.env"

require_root
[ -f "$BOOTCFG" ] || die "$BOOTCFG not found — is this Raspberry Pi OS (Bookworm/Trixie)?"

# The ,drm variant of the piscreen overlay needs the DRM panel driver
# introduced in Linux 6.11.
kver="$(uname -r | grep -oE '^[0-9]+\.[0-9]+')"
if ! printf '6.11\n%s\n' "$kver" | sort -V -C; then
  warn "Kernel $(uname -r) is older than 6.11 — 'piscreen,drm' may not work."
  warn "Update first: sudo apt update && sudo apt full-upgrade, then reboot."
fi

# Refuse to layer on top of LCD-show damage.
if grep -Eq '^\s*dtoverlay=(mhs35|waveshare35|tft35)' "$BOOTCFG"; then
  die "Legacy LCD-show overlay found in $BOOTCFG. Run: sudo ./recover-from-lcd-show.sh first."
fi
if grep -Eq '^\s*(hdmi_cvt|hdmi_mode=87)' "$BOOTCFG"; then
  die "Forced legacy HDMI mode found in $BOOTCFG (LCD-show leftover). Run: sudo ./recover-from-lcd-show.sh first."
fi
if ! grep -Eq '^\s*dtoverlay=vc4-kms-v3d' "$BOOTCFG"; then
  warn "vc4-kms-v3d is not enabled in $BOOTCFG — your config is not stock."
  warn "The DRM path requires KMS. Consider: sudo ./recover-from-lcd-show.sh"
fi

block="$MARK_BEGIN
# [all] resets any [cm4]/[pi4]/... section filter left above this block;
# without it the overlay can be silently skipped on a Pi 5.
[all]
dtparam=spi=on
dtoverlay=piscreen,drm,speed=${PANEL_SPEED},rotate=${PANEL_ROTATE}
# NOTE: do NOT add a separate 'dtoverlay=ads7846' line. The piscreen overlay
# already declares its own touch controller on SPI0 CS1 / GPIO17; a second
# declaration conflicts on the chipselect and pen IRQ, and BOTH fail to probe.
$MARK_END"

backup_file "$BOOTCFG"
write_block "$BOOTCFG" "$MARK_BEGIN" "$MARK_END" "$block"
log "piscreen,drm block written to $BOOTCFG"
log "Reboot now, then run steps/02-verify-boot.sh"
