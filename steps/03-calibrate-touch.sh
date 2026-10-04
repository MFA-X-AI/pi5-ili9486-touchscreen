#!/usr/bin/env bash
# Step 3: interactive touch calibration with on-screen crosshairs.
#
# Shows a full-screen page on the panel with 5 crosshairs (4 near the corners and
# 1 in the centre), twice:
#   round 1  the taps are fitted to a full affine matrix (lib/touch_fit.py)
#   round 2  the same targets again, to measure how accurate that matrix is
# The result is printed here and shown on the panel.
# Taps are read from `libinput debug-events`, which reports raw (uncalibrated)
# positions, so whatever matrix is installed right now does not affect the result.
#
# Why a full fit: on an MHS35 + Pi 5 the touch axes can be swapped relative to
# the display, so taps land mirrored across the diagonal (top-left registers at
# bottom-right). Correcting that takes the off-diagonal terms of the matrix;
# scale and offset alone cannot.
#
# Needs: a logged-in desktop session showing on the panel, chromium, libinput-tools.
# Result goes to calibration.env for steps/04-persist.sh.
set -euo pipefail
# Running as root: don't leave root-owned __pycache__ in the user's checkout.
export PYTHONDONTWRITEBYTECODE=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../defaults.env
source "$SCRIPT_DIR/../defaults.env"

# Must match the T array in files/calibrate.html.
TARGETS="0.1,0.1;0.9,0.1;0.9,0.9;0.1,0.9;0.5,0.5"
N_TARGETS=5
# A check-round rms above this (in % of the screen) is reported as poor.
GOOD_RMS=2.5

require_root
command -v libinput >/dev/null 2>&1 || die "libinput CLI not found: sudo apt install libinput-tools"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
browser="$(chromium_bin)"
[ -n "$browser" ] || die "chromium not found: sudo apt install chromium"

ev="$(touch_event_device)"
[ -n "$ev" ] || die "No ADS7846 touch device found — run steps/02-verify-boot.sh first."
user="$(desktop_user)"

transform="$(current_transform "$user")"
case "$transform" in
  normal|90|180|270) ;;
  "") die "Could not read the transform of $OUTPUT_NAME from wlr-randr (is the desktop session running?)" ;;
  *) die "Transform '$transform' is not supported by the calibration (flipped transforms are not handled)." ;;
esac
log "Touch device /dev/input/$ev, output $OUTPUT_NAME at transform $transform"
[ "$transform" = 270 ] || warn "Only transform 270 has been verified on hardware; check the results below carefully."

work="$(mktemp -d)"
cp "$SCRIPT_DIR/../files/calibrate.html" "$work/"
# chromium runs as the desktop user and writes its profile here.
chown -R "$user" "$work"
taplog="$work/taps.log"
page_pid=""
cleanup() {
  [ -n "${cap_pid:-}" ] && kill "$cap_pid" 2>/dev/null || true
  [ -n "$page_pid" ] && kill "$page_pid" 2>/dev/null || true
  # chromium forks; stop whatever is left of the instance we started (its profile dir is unique).
  pkill -f -- "--user-data-dir=$work/[p]rofile" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

stdbuf -oL libinput debug-events --device "/dev/input/$ev" > "$taplog" 2>&1 &
cap_pid=$!

# A separate profile, so it never touches the user's browser or a running kiosk.
in_session "$user" "$browser" --user-data-dir="$work/profile" --kiosk --app="file://$work/calibrate.html" \
  --ozone-platform=wayland --password-store=basic --no-first-run --noerrdialogs >"$work/browser.log" 2>&1 &
page_pid=$!
sleep 5
if ! kill -0 "$page_pid" 2>/dev/null; then
  err "The calibration page did not stay open. Browser output:"
  grep -v 'dbus' "$work/browser.log" | tail -15 >&2
  exit 1
fi

echo
log "A page with a red cross is opening on the panel."
log "Tap the centre of each cross with a stylus (touch pen) — it is a resistive panel."
log "There are $((N_TARGETS * 2)) taps: $N_TARGETS to calibrate, then the same $N_TARGETS again to check."
warn "If an HDMI monitor is also connected and the page opens there, move it to the panel or unplug HDMI."
echo

# Wait for all taps (counted with the same debounce as touch_fit.py), up to 3 minutes.
want=$((N_TARGETS * 2)) got=0
for _ in $(seq 1 180); do
  got="$(python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/../lib'); import touch_fit; print(len(touch_fit.taps('$taplog')))")"
  [ "$got" -ge "$want" ] && break
  sleep 1
done
[ "$got" -ge "$want" ] || die "Only $got of $want taps received within 3 minutes."

echo
fit_out="$(python3 "$SCRIPT_DIR/../lib/touch_fit.py" fit --log "$taplog" --transform "$transform" --targets "$TARGETS")"
echo "$fit_out" | grep -v '^MATRIX '
matrix="$(echo "$fit_out" | sed -n 's/^MATRIX //p')"
echo
check_out="$(python3 "$SCRIPT_DIR/../lib/touch_fit.py" check --log "$taplog" --transform "$transform" --targets "$TARGETS" --skip "$N_TARGETS" --matrix "$matrix" --js "$work/results.js" --good "$GOOD_RMS")"
chown "$user" "$work/results.js" 2>/dev/null || true
echo "$check_out" | grep -v '^RMS '
rms="$(echo "$check_out" | sed -n 's/^RMS //p')"
echo

log "Calibration matrix: $matrix"
if awk -v r="$rms" -v g="$GOOD_RMS" 'BEGIN { exit !(r <= g) }'; then
  log "Check round: ${rms}% rms error — good."
else
  warn "Check round: ${rms}% rms error, above ${GOOD_RMS}%. Taps may have missed the crosses; consider running this step again."
fi

out="$SCRIPT_DIR/../calibration.env"
printf 'CAL_MATRIX="%s"\n' "$matrix" > "$out"
# Keep it readable/removable by the invoking user, not root.
chown "$user:$(id -gn "$user")" "$out" 2>/dev/null || true
log "Saved to $out"
log "Next: sudo steps/04-persist.sh, then log out/in (or reboot) to apply."

# The panel shows the same result; leave it up until the user taps once more (max 60 s).
log "The result is also on the panel. Tap it once to close (closes by itself after 60 s)."
for _ in $(seq 1 60); do
  [ "$(python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/../lib'); import touch_fit; print(len(touch_fit.taps('$taplog')))")" -gt "$want" ] && break
  sleep 1
done
