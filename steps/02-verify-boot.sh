#!/usr/bin/env bash
# Step 2: after rebooting with the piscreen,drm overlay, verify the stack is
# actually healthy. Every check here corresponds to a real failure mode.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../defaults.env
source "$SCRIPT_DIR/../defaults.env"

pass=0; fail=0
ok()  { log "$*"; pass=$((pass + 1)); }
bad() { err "$*"; fail=$((fail + 1)); }

# 1. Panel registered as a DRM connector?
if grep -q '^connected$' /sys/class/drm/card*-"$OUTPUT_NAME"/status 2>/dev/null; then
  ok "DRM connector $OUTPUT_NAME is connected"
else
  bad "No connected DRM connector named $OUTPUT_NAME (panel did not probe — check wiring, kernel >= 6.11, and dmesg)"
fi

# 2. Touch controller probed? (piscreen's built-in ADS7846)
if grep -q 'ADS7846' /proc/bus/input/devices; then
  ok "ADS7846 touch controller present ($(touch_event_device))"
else
  bad "ADS7846 touch controller missing. If config.txt has a standalone 'dtoverlay=ads7846' line, remove it — it conflicts with piscreen's built-in touch and kills both."
fi

# 3. Booting graphically? (raspi-config can lie; systemd is authoritative)
target="$(systemctl get-default 2>/dev/null)"
if [ "$target" = "graphical.target" ]; then
  ok "systemd default target is graphical.target"
else
  bad "systemd default target is '$target', not graphical.target — the display manager never starts. Fix: sudo systemctl set-default graphical.target"
fi

# 4. Wayland session running? (wlr-randr and Pi Connect both require it)
if pgrep -x labwc >/dev/null || pgrep -x wayfire >/dev/null; then
  ok "Wayland compositor is running"
else
  bad "No Wayland compositor (labwc/wayfire) running. An X11 session cannot drive this setup — check /etc/lightdm/lightdm.conf sessions and ~/.bash_profile for a leftover 'startx' stub."
fi

# 5. No legacy leftovers?
if pgrep -x fbcp >/dev/null; then
  bad "fbcp is running — LCD-show leftover. It cannot work on Pi 5 (DispmanX removed). Run: sudo ./recover-from-lcd-show.sh"
else
  ok "No fbcp process"
fi
if grep -Eq '^\s*dtoverlay=ads7846' "$BOOTCFG" 2>/dev/null; then
  bad "Standalone 'dtoverlay=ads7846' line in $BOOTCFG — conflicts with piscreen's built-in touch. Remove it."
else
  ok "No conflicting ads7846 overlay line"
fi

# 6. Autologin getty racing the display manager? (LCD-show leftover)
if [ -d /etc/systemd/system/getty@tty1.service.d ]; then
  bad "getty@tty1 autologin drop-in exists — can bypass the display manager. Fix: sudo rm -r /etc/systemd/system/getty@tty1.service.d"
else
  ok "No getty@tty1 autologin drop-in"
fi

# 7. Compositor actually sees the panel? (only checkable from inside a session)
if command -v wlr-randr >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  if wlr-randr 2>/dev/null | grep -q "^$OUTPUT_NAME"; then
    ok "wlr-randr sees output $OUTPUT_NAME"
  else
    bad "wlr-randr does not list $OUTPUT_NAME"
  fi
else
  warn "Skipping wlr-randr check (not inside a Wayland session, or wlr-randr not installed: sudo apt install wlr-randr)"
fi

echo
if [ "$fail" -eq 0 ]; then
  log "All checks passed ($pass). Next: steps/03-calibrate-touch.sh (or steps/04-persist.sh --use-defaults)"
else
  die "$fail check(s) failed, $pass passed. Fix the failures above before continuing."
fi
