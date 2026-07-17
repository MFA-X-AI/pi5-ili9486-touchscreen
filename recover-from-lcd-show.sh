#!/usr/bin/env bash
# Recovery from goodtft/LCD-show (MHS35-show, waveshare35a-show, and friends)
# on Raspberry Pi OS Bookworm/Trixie. Undoes everything the installer breaks:
#
#   1. Restores a clean stock /boot/firmware/config.txt (KMS back on,
#      forced 480x320 HDMI mode gone, fbtft overlays gone).
#   2. Removes fbcp / con2fbmap from /etc/rc.local (fbcp is dead on Pi 5 —
#      DispmanX no longer exists).
#   3. Deletes the ~/.bash_profile "startx" stub that silently truncates PATH
#      (bash login shells prefer .bash_profile and skip .bashrc entirely).
#   4. Sets the systemd default back to graphical.target — this, not
#      raspi-config's flag, decides whether the display manager starts.
#   5. Removes the getty@tty1 autologin drop-in that races the display manager.
#   6. Points LightDM back at the Wayland session (Pi Connect requires Wayland).
#   7. Quarantines stray X11 calibration/fbturbo configs and LCD-show .dtbo files.
#
# Everything modified is backed up first (*.bak-<timestamp>). Idempotent.
# The vendor's own system_restore.sh does NOT do most of this and may restore
# from an already-polluted backup — do not rely on it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root
[ -d /boot/firmware ] || die "/boot/firmware not found — this script targets Pi OS Bookworm/Trixie."

echo "This will rewrite $BOOTCFG with a stock template and undo LCD-show's"
echo "system changes. Backups are taken of every file touched."
printf 'Proceed? [y/N] '
read -r ans
[ "${ans,,}" = "y" ] || exit 1

user="$(desktop_user)"
home_dir="$(getent passwd "$user" | cut -d: -f6)"
quarantine="/var/backups/lcd-show-quarantine-$(date +%Y%m%d-%H%M%S)"

## 1. Stock config.txt
backup_file "$BOOTCFG"
cp "$SCRIPT_DIR/files/config.txt.stock" "$BOOTCFG"   # plain cp: vfat has no modes
log "Stock config.txt installed (vc4-kms-v3d on, no forced HDMI mode, no fbtft)"

## 2. rc.local: strip fbcp / con2fbmap lines
if [ -f /etc/rc.local ] && grep -Eq 'fbcp|con2fbmap' /etc/rc.local; then
  backup_file /etc/rc.local
  sed -i -E '/fbcp|con2fbmap/d' /etc/rc.local
  log "Removed fbcp/con2fbmap from /etc/rc.local"
fi

## 3. .bash_profile startx stub
profile="$home_dir/.bash_profile"
if [ -f "$profile" ] && grep -Eq 'startx|FRAMEBUFFER=/dev/fb1' "$profile"; then
  backup_file "$profile"
  rm -f "$profile"
  log "Deleted LCD-show's $profile stub (login shells now read .profile/.bashrc again)"
fi

## 4. Boot graphically. systemctl is authoritative; raspi-config's flag can lie.
if [ "$(systemctl get-default)" != "graphical.target" ]; then
  systemctl set-default graphical.target
  log "systemd default target set to graphical.target"
fi

## 5. getty autologin drop-in
if [ -d /etc/systemd/system/getty@tty1.service.d ]; then
  mkdir -p "$quarantine"
  mv /etc/systemd/system/getty@tty1.service.d "$quarantine/"
  systemctl daemon-reload
  log "Removed getty@tty1 autologin drop-in (quarantined to $quarantine)"
fi

## 6. LightDM back to Wayland
lightdm=/etc/lightdm/lightdm.conf
if [ -f "$lightdm" ]; then
  wl_session=""
  # rpd-* on Trixie and later Bookworm; LXDE-pi-* on earlier Bookworm.
  for s in rpd-labwc LXDE-pi-labwc rpd-wayfire LXDE-pi-wayfire; do
    if [ -f "/usr/share/wayland-sessions/$s.desktop" ]; then
      wl_session="$s"; break
    fi
  done
  if [ -n "$wl_session" ]; then
    backup_file "$lightdm"
    sed -i -E "s/^(user-session)=.*/\1=$wl_session/; s/^(autologin-session)=.*/\1=$wl_session/" "$lightdm"
    sed -i -E "s/^(greeter-session)=pi-greeter-x$/\1=pi-greeter/" "$lightdm"
    log "LightDM sessions set to $wl_session (Wayland)"
  else
    warn "No labwc/wayfire Wayland session found — leaving $lightdm untouched."
  fi
fi

## 7. Quarantine X11/fbtft leftovers and LCD-show device-tree blobs
leftovers=(
  /etc/X11/xorg.conf.d/99-calibration.conf
  /etc/X11/xorg.conf.d/99-fbturbo.conf
  /usr/share/X11/xorg.conf.d/99-fbturbo.conf
  /etc/modules-load.d/fbtft.conf
)
for f in "${leftovers[@]}"; do
  if [ -e "$f" ]; then
    # Keep the original path: two leftovers can share a file name.
    mkdir -p "$quarantine$(dirname "$f")"
    mv "$f" "$quarantine$f"
    log "Quarantined $f"
  fi
done
for dtbo in /boot/firmware/overlays/mhs35*.dtbo /boot/firmware/overlays/waveshare35a*.dtbo /boot/firmware/overlays/tft35a*.dtbo; do
  if [ -e "$dtbo" ]; then
    mkdir -p "$quarantine"
    mv "$dtbo" "$quarantine/"
    log "Quarantined $dtbo"
  fi
done
[ -d "$quarantine" ] && log "Quarantined files kept in $quarantine (delete when happy)"

echo
log "Recovery complete. Reboot now: sudo reboot"
log "After reboot you should land in a Wayland desktop on HDMI."
log "Then bring the panel up the modern way: sudo ./setup.sh"
