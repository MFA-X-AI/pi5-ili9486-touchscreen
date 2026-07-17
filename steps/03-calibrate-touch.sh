#!/usr/bin/env bash
# Step 3: interactive 4-corner touch calibration.
# Measures raw tap positions with libinput debug-events, rounds outward, and
# computes the affine calibration matrix libinput expects:
#   scale_x  0        offset_x
#   0        scale_y  offset_y
# Result is written to calibration.env for steps/04-persist.sh to pick up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_root
command -v libinput >/dev/null 2>&1 || die "libinput CLI not found: sudo apt install libinput-tools"

ev="$(touch_event_device)"
[ -n "$ev" ] || die "No ADS7846 touch device found — run steps/02-verify-boot.sh first."
dev="/dev/input/$ev"
log "Touch device: $dev"

# If a calibration matrix is already installed, measurements may come back
# post-calibration (build-dependent) and the math below would be wrong.
if [ -e "$HWDB_FILE" ]; then
  warn "$HWDB_FILE already exists — an old matrix may distort measurements."
  warn "Remove it and re-trigger first for a clean run:"
  warn "  sudo rm $HWDB_FILE && sudo systemd-hwdb update && sudo udevadm trigger"
  printf 'Continue anyway? [y/N] '
  read -r ans
  [ "${ans,,}" = "y" ] || exit 1
fi

# Capture one TOUCH_DOWN and print its "x/y" position (percent of screen).
capture_tap() {
  local line
  line="$( (timeout 20 stdbuf -oL libinput debug-events --device "$dev" 2>/dev/null || true) \
           | grep -m1 'TOUCH_DOWN' || true)"
  [ -n "$line" ] || return 1
  printf '%s\n' "$line" | grep -oE '[0-9]+\.[0-9]+/ *[0-9]+\.[0-9]+' | head -1 | tr -d ' '
}

corners=("TOP-LEFT" "TOP-RIGHT" "BOTTOM-RIGHT" "BOTTOM-LEFT")
xs=(); ys=()
echo
log "Tap each corner of the PANEL as it is prompted (as close to the corner as you can)."
log "You have 20 seconds per tap."
echo
for c in "${corners[@]}"; do
  printf '\033[1m  >>> Tap the %s corner now...\033[0m\n' "$c"
  p="$(capture_tap)" || die "No tap detected within 20s for $c corner."
  xs+=("${p%/*}"); ys+=("${p#*/}")
  log "  $c: x=${p%/*}%  y=${p#*/}%"
done

# Order matches the corners array: 0=TL 1=TR 2=BR 3=BL.
# Round OUTWARD (floor mins, ceil maxes) — fingers never hit the exact corner.
read -r xmin xmax ymin ymax matrix <<EOF
$(awk -v tlx="${xs[0]}" -v trx="${xs[1]}" -v brx="${xs[2]}" -v blx="${xs[3]}" \
      -v tly="${ys[0]}" -v try_="${ys[1]}" -v bry="${ys[2]}" -v bly="${ys[3]}" '
  function min(a, b) { return a < b ? a : b }
  function max(a, b) { return a > b ? a : b }
  BEGIN {
    xmin = int(min(tlx, blx))          # floor
    xmax = int(max(trx, brx)) + 1      # ceil
    ymin = int(min(tly, try_))
    ymax = int(max(bry, bly)) + 1
    sx = 100 / (xmax - xmin); ox = -xmin / (xmax - xmin)
    sy = 100 / (ymax - ymin); oy = -ymin / (ymax - ymin)
    printf "%d %d %d %d %.5f 0 %.5f 0 %.5f %.5f\n", xmin, xmax, ymin, ymax, sx, ox, sy, oy
  }')
EOF

echo
log "Measured active area: x=[$xmin..$xmax]%  y=[$ymin..$ymax]%"
log "Calibration matrix:   $matrix"

out="$SCRIPT_DIR/../calibration.env"
printf 'CAL_MATRIX="%s"\n' "$matrix" > "$out"
# Keep it readable/removable by the invoking user, not root.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  chown "$SUDO_USER:$SUDO_USER" "$out" 2>/dev/null || true
fi
log "Saved to $out"
log "Next: sudo steps/04-persist.sh"
