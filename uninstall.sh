#!/usr/bin/env bash
# Remove everything this repo installed. Leaves your system otherwise untouched.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

user="$(desktop_user)"
group="$(id -gn "$user")"
home_dir="$(getent passwd "$user" | cut -d: -f6)"
[ -n "$home_dir" ] || die "Could not resolve home directory for user '$user'"

# config.txt block
if [ -f "$BOOTCFG" ] && grep -qF "$MARK_BEGIN" "$BOOTCFG"; then
  backup_file "$BOOTCFG"
  tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) == 1 { skip = 1; next }
    index($0, e) == 1 { skip = 0; next }
    !skip { print }
  ' "$BOOTCFG" > "$tmp"
  cat "$tmp" > "$BOOTCFG"; rm -f "$tmp"
  log "Removed piscreen,drm block from $BOOTCFG"
fi

# hwdb calibration
if [ -e "$HWDB_FILE" ]; then
  backup_file "$HWDB_FILE"
  rm -f "$HWDB_FILE"
  systemd-hwdb update
  udevadm trigger
  log "Removed $HWDB_FILE"
fi

# labwc autostart block
autostart="$home_dir/.config/labwc/autostart"
if [ -f "$autostart" ] && grep -qF "$AUTOSTART_BEGIN" "$autostart"; then
  backup_file "$autostart"
  tmp="$(mktemp)"
  awk -v b="$AUTOSTART_BEGIN" -v e="$AUTOSTART_END" '
    index($0, b) == 1 { skip = 1; next }
    index($0, e) == 1 { skip = 0; next }
    !skip { print }
  ' "$autostart" > "$tmp"
  cat "$tmp" > "$autostart"; rm -f "$tmp"
  chown "$user:$group" "$autostart"
  log "Removed output block from $autostart"
fi

# labwc rc.xml touch mapping
rcxml="$home_dir/.config/labwc/rc.xml"
if [ -f "$rcxml" ] && grep -qF "$RCXML_BEGIN" "$rcxml"; then
  backup_file "$rcxml"
  remove_block "$rcxml" "$RCXML_BEGIN" "$RCXML_END"
  chown "$user:$group" "$rcxml"
  log "Removed touch mapping from $rcxml"
fi

# saved rotation
if [ -e "$TRANSFORM_STATE" ]; then
  rm -rf "$(dirname "$TRANSFORM_STATE")"
  log "Removed saved rotation $TRANSFORM_STATE"
fi

log "Uninstalled. Reboot to release the panel: sudo reboot"
