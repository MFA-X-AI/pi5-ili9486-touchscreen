# LCD-show on modern Raspberry Pi OS: known issues

Reference for what `goodtft/LCD-show` (and the related `lcdwiki` variants)
changes on a system, why each change breaks current Raspberry Pi OS
(Bookworm/Trixie) and the Pi 5 in particular, and how `recover-from-lcd-show.sh`
addresses it.

## Changes made by the installer

| # | Change | Effect on modern Pi OS | Recovery |
|---|---|---|---|
| 1 | `raspi-config nonint do_wayland W1` (switch to X11) | Raspberry Pi Connect screen sharing requires Wayland (`wlr-screencopy`); it stops working | LightDM session set back to `rpd-labwc` / `rpd-wayfire` |
| 2 | `raspi-config nonint do_boot_behaviour B2` (console autologin) | Default target becomes `multi-user.target`; the display manager never starts | `systemctl set-default graphical.target`; getty autologin drop-in removed |
| 3 | Replaces `/boot/firmware/config.txt` with a legacy template | `dtoverlay=vc4-kms-v3d` commented out (no KMS), modern defaults dropped, HDMI forced to 480×320 via `hdmi_cvt`/`hdmi_mode=87` | Stock template reinstalled |
| 4 | Installs an `fbtft` overlay (`mhs35`/`waveshare35a`) and builds `rpi-fbcp` | `fbcp` requires the DispmanX API, which was removed on Pi 5 — the panel cannot work through this path at all | Overlay lines removed; `fbcp`/`con2fbmap` stripped from `/etc/rc.local`; stray `.dtbo` files quarantined |
| 5 | Overwrites `~/.bash_profile` with a `startx` stub | Bash login shells prefer `~/.bash_profile` and skip `~/.bashrc`/`~/.profile`, so user PATH entries (nvm, `~/.local/bin`, npm globals) silently disappear; the stub's `startx` also races the display manager | Stub deleted (backed up first) |

## Why the vendor `system_restore.sh` is insufficient

- It restores from `.system_backup/`, which is taken at the top of each
  installer run. If any LCD-show-family installer ran before, the backup
  already contains a polluted `config.txt` and `rc.local`.
- It does not revert the `raspi-config` changes (boot behaviour, Wayland).
- It does not touch `~/.bash_profile`.
- It writes `cmdline.txt` to `/boot/cmdline.txt`; the active file on
  Bookworm/Trixie is `/boot/firmware/cmdline.txt`.
- It reinstalls a 32-bit `armhf` evdev `.deb`, which `dpkg` rejects on 64-bit
  systems, then reboots regardless.

## Failure signatures

Symptoms that indicate LCD-show residue, and how to check for it
(`doctor.sh` automates all of these):

| Symptom | Check | Meaning |
|---|---|---|
| Boots to a text console | `systemctl get-default` | `multi-user.target` → display manager not pulled in. This is authoritative; `raspi-config nonint get_boot_cli` checks a different marker and can disagree |
| Desktop present but X11, Pi Connect broken | `ps -eo tty,pid,cmd \| awk '$1=="tty1"'` | An Xorg/lxsession tree on tty1 means a getty-autologin + `.bash_profile` `startx` chain is bypassing the display manager |
| `rpi-connect-wayvnc.service` restarting every ~5 s in the journal | `journalctl -b -p err` | No Wayland compositor is running. `rpi-connect status` reporting `Screen sharing: allowed` only confirms a session file exists, not a running compositor |
| CLI tools missing from PATH after login | `cat ~/.bash_profile` | Installer stub (`FRAMEBUFFER=/dev/fb1` + `startx`) is suppressing `~/.bashrc`/`~/.profile` |
| HDMI stuck at 480×320 | `grep -E 'hdmi_cvt\|hdmi_mode=87' /boot/firmware/config.txt` | Forced legacy HDMI mode for the `fbcp` copy path |
| Panel dark despite install | n/a on Pi 5 | The `fbcp` pipeline depends on DispmanX, removed on Pi 5 |

## Touch controller conflict (applies to manual setups too)

The `piscreen` overlay declares its own touch controller (`piscreen-ts@1`) on
SPI0 CS1 with the pen IRQ on GPIO17. Adding a separate
`dtoverlay=ads7846,cs=1,penirq=17,...` line makes both claim the same
chipselect and pin, and both fail to probe. Kernel log signature:

```
spi spi0.1: chipselect 1 already in use
pinctrl-rp1: pin gpio17 already requested by spi0.0
```

Use only the `piscreen` overlay; its built-in touch is sufficient. Successful
probe looks like:

```
input: ADS7846 Touchscreen as /devices/.../input/input5
```

## Calibration verification

On some builds `libinput debug-events` prints pre-calibration coordinates
even when a matrix is active. Verify calibration with
`sudo libinput list-devices` and read the `Calibration:` line; digits there
(rather than `identity matrix`) mean the hwdb matrix is applied.

## Performance expectations

An SPI-attached 480×320 panel at 32 MHz sustains roughly 15–25 FPS. This is
the bus bandwidth limit, not a configuration problem. The panel is suitable
for status displays and simple controls, not video or fast interaction.
