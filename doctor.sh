#!/usr/bin/env bash
# Read-only diagnostics. Run any time; changes nothing.
# Each check corresponds to a known failure mode; see docs/lcd-show-issues.md.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=defaults.env
source "$SCRIPT_DIR/defaults.env"

section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

section "System"
echo "  Kernel:       $(uname -r)  (piscreen,drm needs >= 6.11)"
echo "  Model:        $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
echo "  Default boot: $(systemctl get-default 2>/dev/null)  (want graphical.target; this is authoritative, raspi-config's flag is not)"

section "config.txt ($BOOTCFG)"
if [ -f "$BOOTCFG" ]; then
  grep -Eq '^\s*dtoverlay=vc4-kms-v3d' "$BOOTCFG" \
    && echo "  [ok]   vc4-kms-v3d (KMS) enabled" \
    || echo "  [FAIL] vc4-kms-v3d missing/commented — legacy config, DRM path cannot work"
  grep -qF "$MARK_BEGIN" "$BOOTCFG" \
    && echo "  [ok]   piscreen,drm block present" \
    || echo "  [--]   piscreen,drm block not installed yet (run steps/01-enable-display.sh)"
  grep -Eq '^\s*dtoverlay=(mhs35|waveshare35|tft35)' "$BOOTCFG" \
    && echo "  [FAIL] legacy LCD-show fbtft overlay present — run recover-from-lcd-show.sh"
  grep -Eq '^\s*(hdmi_cvt|hdmi_mode=87)' "$BOOTCFG" \
    && echo "  [FAIL] forced legacy HDMI 480x320 mode present (LCD-show leftover)"
  grep -Eq '^\s*dtoverlay=ads7846' "$BOOTCFG" \
    && echo "  [FAIL] standalone ads7846 overlay — conflicts with piscreen's built-in touch, both die"
else
  echo "  [FAIL] $BOOTCFG not found"
fi

section "Display (DRM)"
found=0
for c in /sys/class/drm/card*-*/status; do
  [ -e "$c" ] || continue
  name="$(basename "$(dirname "$c")")"
  echo "  $name: $(cat "$c")"
  case "$name" in *SPI-1) found=1 ;; esac
done
[ "$found" = 1 ] || echo "  [FAIL] no SPI-1 connector — panel not registered (overlay missing, kernel too old, or wiring)"

if command -v wlr-randr >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  hz="$(wlr-randr 2>/dev/null | awk -v o="$OUTPUT_NAME" '$1 == o { on = 1; next } /^[^ ]/ { on = 0 } on && /current/ { for (i = 1; i <= NF; i++) if ($i == "Hz") print $(i - 1); exit }')"
  if [ -n "$hz" ]; then
    awk -v h="$hz" 'BEGIN { exit !(h < 1) }' \
      && echo "  [FAIL] $OUTPUT_NAME refresh is $hz Hz (driver placeholder) — browsers draw ~1 fps. Re-run steps/04-persist.sh (sets OUTPUT_MODE)" \
      || echo "  [ok]   $OUTPUT_NAME refresh $hz Hz"
  fi
else
  echo "  [--]   run from inside the desktop session to check the output refresh rate"
fi

section "Touch"
if grep -q 'ADS7846' /proc/bus/input/devices; then
  echo "  [ok]   ADS7846 present as $(touch_event_device)  (hwdb match: $(touch_hwdb_match))"
else
  echo "  [FAIL] ADS7846 not found in input devices"
fi
[ -e "$HWDB_FILE" ] \
  && echo "  [ok]   calibration file: $HWDB_FILE" \
  || echo "  [--]   no persisted calibration (steps/04-persist.sh)"
if [ "$(id -u)" -eq 0 ] && command -v libinput >/dev/null 2>&1; then
  cal="$(libinput list-devices 2>/dev/null | grep -A20 'ADS7846' | grep 'Calibration:' | head -1)"
  [ -n "$cal" ] && echo "  active ${cal# }" \
                || echo "  [--]   no active calibration reported by libinput"
  echo "         (note: 'libinput debug-events' shows raw, PRE-calibration coords; list-devices shows the matrix)"
  echo "         (a loaded matrix can still be wrong — steps/03-calibrate-touch.sh measures where taps land)"
else
  echo "  [--]   run as root with libinput-tools installed to see the active matrix"
fi

section "Session / Wayland"
if pgrep -x labwc >/dev/null || pgrep -x wayfire >/dev/null; then
  echo "  [ok]   Wayland compositor running ($(pgrep -x labwc >/dev/null && echo labwc || echo wayfire))"
else
  echo "  [FAIL] no Wayland compositor — X11 or console session"
fi
pgrep -x fbcp >/dev/null \
  && echo "  [FAIL] fbcp running — dead-end on Pi 5 (DispmanX removed), run recovery" \
  || echo "  [ok]   no fbcp"
[ -d /etc/systemd/system/getty@tty1.service.d ] \
  && echo "  [FAIL] getty@tty1 autologin drop-in — can bypass the display manager (rogue X on vt1)" \
  || echo "  [ok]   no getty@tty1 autologin drop-in"
u="$(desktop_user)"; h="$(getent passwd "$u" | cut -d: -f6)"
if [ -f "$h/.bash_profile" ] && grep -Eq 'startx|FRAMEBUFFER=/dev/fb1' "$h/.bash_profile"; then
  echo "  [FAIL] $h/.bash_profile contains LCD-show's startx stub — also silently truncates PATH"
else
  echo "  [ok]   no .bash_profile startx stub"
fi
# Rogue display session outside the display manager?
rogue="$(ps -eo tty=,cmd= | awk '$1=="tty1" && /Xorg|xinit|startx/ {print; exit}')"
[ -n "$rogue" ] && echo "  [FAIL] rogue X session on tty1: $rogue"

section "Packages"
broken="$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 'xinput-calibrator:armhf' 'xserver-xorg-input-evdev:armhf' 2>/dev/null | awk '$1 !~ /^(ii|un)/ { print $2 }' | tr '\n' ' ')"
[ -n "$broken" ] \
  && echo "  [FAIL] half-installed armhf packages from LCD-show: $broken— every apt install fails. Run recover-from-lcd-show.sh (purges them)" \
  || echo "  [ok]   no half-installed LCD-show armhf packages"

section "Pi Connect (optional)"
if systemctl --user list-unit-files rpi-connect-wayvnc.service >/dev/null 2>&1; then
  state="$(systemctl --user is-active rpi-connect-wayvnc.service 2>/dev/null || true)"
  echo "  rpi-connect-wayvnc: ${state:-unknown}"
  echo "  (crashlooping every ~5s in 'journalctl --user -u rpi-connect-wayvnc' = it can't find a Wayland compositor,"
  echo "   regardless of what 'rpi-connect status' claims — that only checks a session file exists)"
else
  echo "  not installed / not checkable from this shell"
fi
echo
