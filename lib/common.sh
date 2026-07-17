#!/usr/bin/env bash
# Shared helpers, sourced by every script in this repo.

BOOTCFG="/boot/firmware/config.txt"
MARK_BEGIN="# >>> spi-lcd piscreen,drm BEGIN"
MARK_END="# <<< spi-lcd piscreen,drm END"
AUTOSTART_BEGIN="# >>> spi-lcd output BEGIN"
AUTOSTART_END="# <<< spi-lcd output END"
HWDB_FILE="/etc/udev/hwdb.d/61-spi-lcd-touch.hwdb"
# labwc rc.xml block mapping the touch controller to the panel's output.
RCXML_BEGIN="<!-- >>> spi-lcd touch BEGIN -->"
RCXML_END="<!-- <<< spi-lcd touch END -->"
# Compositor transform requested by *-show / rotate.sh, kept across the reboot
# between setup runs so a later plain ./setup.sh does not revert to the default.
TRANSFORM_STATE="/var/lib/spi-lcd/output_transform"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "This script needs root. Run: sudo $0"
}

# The desktop user (owner of the labwc session), even when running under sudo.
desktop_user() {
  local u="${SUDO_USER:-}"
  if [ -z "$u" ] || [ "$u" = "root" ]; then
    u="$(logname 2>/dev/null || true)"
  fi
  if [ -z "$u" ] || [ "$u" = "root" ]; then
    die "Cannot determine the desktop user. Run this with sudo from the desktop user's account, not from a root shell."
  fi
  echo "$u"
}

# Timestamped backup next to the original. Never overwrites a previous backup.
backup_file() {
  local f="$1"
  [ -e "$f" ] || return 0
  local b="${f}.bak-$(date +%Y%m%d-%H%M%S)" n=1
  while [ -e "$b" ]; do b="${f}.bak-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n + 1)); done
  # /boot/firmware is vfat: ownership/modes cannot be preserved there.
  cp -a "$f" "$b" 2>/dev/null || cp "$f" "$b"
  log "Backed up $f -> $b"
}

# Replace (or append) a marker-delimited block in a file.
# Any existing block between the markers is removed, trailing blank lines are
# dropped, then the new content (which must itself include the markers) is
# appended after one blank line. Idempotent.
write_block() {
  local f="$1" begin="$2" end="$3" content="$4"
  touch "$f"
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    index($0, b) == 1 { skip = 1; next }
    index($0, e) == 1 { skip = 0; next }
    skip { next }
    /^[[:space:]]*$/ { pending = pending $0 "\n"; next }
    { printf "%s", pending; pending = ""; print }
  ' "$f" > "$tmp"
  printf '\n%s\n' "$content" >> "$tmp"
  cat "$tmp" > "$f"   # cat, not mv: preserves ownership and permissions
  rm -f "$tmp"
}

# Event device node (eventN) of the ADS7846 touch controller, empty if absent.
touch_event_device() {
  awk '/^N:.*ADS7846/ { found = 1 }
       found && /^H:/ { for (i = 1; i <= NF; i++) if ($i ~ /^event/) { print $i; exit } }' \
    /proc/bus/input/devices
}

# Input device name of the ADS7846 touch controller (e.g. "ADS7846 Touchscreen").
touch_device_name() {
  sed -n 's/^N: Name="\(.*ADS7846.*\)"$/\1/p' /proc/bus/input/devices | head -1
}

# Remove a marker-delimited block from a file (no-op if absent).
remove_block() {
  local f="$1" begin="$2" end="$3" tmp
  [ -f "$f" ] && grep -qF "$begin" "$f" || return 0
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    index($0, b) == 1 { skip = 1; next }
    index($0, e) == 1 { skip = 0; next }
    !skip { print }
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
}

# hwdb modalias match for the ADS7846 touch controller, derived from its
# actual bus/vendor/product IDs (e.g. evdev:input:b001Cv0000p1EA6*).
touch_hwdb_match() {
  awk '/^I:/ { bus = $2; ven = $3; pro = $4 }
       /^N:.*ADS7846/ {
         gsub(/Bus=/,     "", bus)
         gsub(/Vendor=/,  "", ven)
         gsub(/Product=/, "", pro)
         printf "evdev:input:b%sv%sp%s*\n", toupper(bus), toupper(ven), toupper(pro)
         exit
       }' /proc/bus/input/devices
}
