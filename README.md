# pi5-ili9486-touchscreen

Sets up 3.5" SPI touchscreens (ILI9486 panel, XPT2046/ADS7846 resistive touch, 480×320) on a Raspberry Pi 5 running current Raspberry Pi OS, using the kernel's DRM driver and Wayland. No `LCD-show`, no `fbcp`, no X11. The panel appears as a second monitor.

## Supported panels

| Panel | LCD-show equivalent | Install command | Status |
|---|---|---|---|
| MHS-3.5" RPi Display (MHS3528) — [lcdwiki](http://www.lcdwiki.com/MHS-3.5inch_RPi_Display) | `MHS35-show` | `sudo ./MHS35-show` | Tested |
| 3.5" RPi Display (MPI3501, waveshare35a clones) — [lcdwiki](http://www.lcdwiki.com/3.5inch_RPi_Display) | `LCD35-show` | `sudo ./LCD35-show` | Same pinout class, untested |
| Other ILI9486 + XPT2046/ADS7846 3.5" SPI panels | — | `sudo ./setup.sh` | Should work |

All commands do the same thing; the per-panel names exist so LCD-show users find the command they know. If your panel uses a different controller (ILI9488, ST7796), the `piscreen` overlay does not match it and this repo does not apply.

## Background: why the vendor installer no longer works

These panels ship with instructions to run [`goodtft/LCD-show`](https://github.com/goodtft/LCD-show) (or an `lcdwiki` variant). That installer was written for the graphics stack Raspberry Pi OS used up to roughly 2020: a legacy framebuffer driver (`fbtft`) for the panel, an X11 desktop, and a helper (`fbcp`) that continuously copies the HDMI framebuffer to the panel over SPI using Broadcom's DispmanX API.

Every part of that stack has since been replaced:

| The installer assumes | Current Raspberry Pi OS (Bookworm/Trixie) | Consequence on a Pi 5 |
|---|---|---|
| DispmanX API for `fbcp` | Removed entirely on Pi 5 | The copy pipeline cannot run; **the panel stays dark no matter what** |
| X11 desktop | Wayland (labwc/Wayfire) by default; Raspberry Pi Connect requires Wayland | Installer force-switches to X11, breaking screen sharing |
| Legacy firmware graphics (`config.txt` without KMS) | KMS driver `vc4-kms-v3d` is mandatory | Installer disables KMS and pins HDMI at 480×320 |
| Old boot flow | systemd `graphical.target` + display manager | Installer sets console autologin; the Pi boots to a text prompt |

So on a Pi 5 with current Pi OS, running `LCD-show` does not merely fail — it leaves the system misconfigured (dark panel, 480×320 HDMI, X11, console boot, overwritten `~/.bash_profile`), and its bundled `system_restore.sh` does not revert most of the damage. The full breakdown is in [docs/lcd-show-issues.md](docs/lcd-show-issues.md); `recover-from-lcd-show.sh` in this repo reverts it.

None of that machinery is needed anymore. Since Linux 6.11 the stock [`piscreen` overlay](https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README) has a `,drm` variant that registers the panel as a native DRM connector (`SPI-1`). The Wayland compositor treats it as a second monitor, and touch is handled by the same overlay. One `config.txt` line replaces the entire legacy stack — that is what this repo sets up (plus touch calibration and rotation/scale persistence).

If you are on an older setup where LCD-show still works for you (Pi 4 or earlier on a legacy/X11 image), you don't need this repo — it targets current Pi OS with kernel ≥ 6.11.

## Part 0: setting up the Pi from scratch

Skip to [Part 1](#part-1-panel-install) if your Pi already runs an up-to-date Raspberry Pi OS desktop.

You need: a Raspberry Pi 5, a microSD card (16 GB+), the official power supply, the panel, and another computer for flashing.

1. **Flash the OS.** Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your computer. Choose:
   - *Device:* Raspberry Pi 5
   - *OS:* Raspberry Pi OS (64-bit) — the default desktop image
   - *Storage:* your microSD card

   When asked to apply OS customisation, select **Edit settings** and set a hostname, username/password, your Wi-Fi network, and enable SSH (Services tab). This lets you reach the Pi without a keyboard or monitor.
2. **Mount the panel.** With the Pi powered off, press the panel onto the GPIO header so that the panel's female connector covers pins 1–26, aligned to the corner of the board (pin 1 is the pin closest to the microSD slot). The panel body sits over the Pi.
3. **First boot.** Insert the card, connect power. Wait 2–3 minutes for first-boot setup. The panel will stay dark for now — that is expected; an HDMI monitor works normally if you have one.
4. **Get a terminal.** Either open a terminal on the desktop (HDMI monitor), or from your computer: `ssh <username>@<hostname>.local`. The [official getting-started guide](https://www.raspberrypi.com/documentation/computers/getting-started.html) covers this in more detail.
5. **Update.** The `,drm` overlay variant needs kernel ≥ 6.11:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```

   After the reboot, check with `uname -r` — the version must be 6.11 or higher.
6. **Install the tools this repo uses:**

   ```bash
   sudo apt install -y git wlr-randr libinput-tools
   ```

## Part 1: panel install

```bash
git clone https://github.com/MFA-X-AI/pi5-ili9486-touchscreen
cd pi5-ili9486-touchscreen
sudo ./MHS35-show      # first run: installs the overlay, then asks for a reboot
sudo reboot
cd pi5-ili9486-touchscreen
sudo ./MHS35-show      # second run: verifies, calibrates touch, persists
```

(Substitute your panel's command from the table above.)

The second run walks you through a 4-corner touch calibration — tap each corner of the panel when prompted. After logging out and back in (or rebooting), the panel is a second monitor: landscape, scaled, calibrated touch, persisted across reboots.

### All commands

| Command | Function |
|---|---|
| `sudo ./MHS35-show [0\|90\|180\|270]` / `sudo ./LCD35-show [...]` | Install (default rotation 90, as in LCD-show) |
| `sudo ./rotate.sh <angle>` | Change display rotation. No reboot. Touch is not re-mapped; see Limitations |
| `sudo ./LCD-hdmi` | Remove everything (overlay, calibration, autostart, touch mapping) |
| `sudo ./recover-from-lcd-show.sh` | Revert a system previously modified by LCD-show, including the changes `system_restore.sh` misses |
| `./doctor.sh` | Read-only diagnostics |
| `sudo ./setup.sh` | What the `*-show` wrappers call; equivalent |
| `sudo ./uninstall.sh` | Same as `LCD-hdmi` |

### Recovering from LCD-show

If you already ran an LCD-show installer and the system is misbehaving (console boot, 480×320 HDMI, missing PATH entries):

```bash
sudo ./recover-from-lcd-show.sh
sudo reboot
sudo ./MHS35-show
```

### Diagnostics

```bash
./doctor.sh            # run with sudo for full detail
```

## What gets installed where

| Item | Location | Mechanism |
|---|---|---|
| Panel + touch driver | `/boot/firmware/config.txt` ([docs](https://www.raspberrypi.com/documentation/computers/config_txt.html)) | `dtoverlay=piscreen,drm,speed=32000000,rotate=90` in a marker-delimited block |
| Touch calibration | `/etc/udev/hwdb.d/61-spi-lcd-touch.hwdb` ([hwdb docs](https://www.freedesktop.org/software/systemd/man/latest/hwdb.html)) | [`LIBINPUT_CALIBRATION_MATRIX`](https://wayland.freedesktop.org/libinput/doc/latest/absolute-axes.html#calibration-of-absolute-devices), keyed to the ADS7846's bus/vendor/product ID |
| Rotation + scale | `~/.config/labwc/autostart` | [`wlr-randr`](https://gitlab.freedesktop.org/emersion/wlr-randr)` --output SPI-1 --transform 270 --scale 0.75 &` |
| Touch → panel mapping | `~/.config/labwc/rc.xml` ([docs](https://labwc.github.io/labwc-config.5.html#touch)) | `<touch deviceName="ADS7846 Touchscreen" mapToOutput="SPI-1" />`, so touch stays on the panel when HDMI is also connected |

Every file touched is backed up first (`*.bak-<timestamp>`), all inserted blocks are marker-delimited, and the scripts are idempotent. `./uninstall.sh` removes all of them.

Tunables (rotation, scale, SPI speed, default calibration matrix) are in [`defaults.env`](defaults.env).

## Touch calibration

`steps/03-calibrate-touch.sh` runs a 4-corner procedure:

1. Captures each corner tap via `libinput debug-events` (coordinates in % of screen).
2. Rounds the measured extremes outward (taps never reach the exact corner).
3. Computes the affine matrix libinput expects:
   `scale_x = 100/(xmax−xmin)`, `offset_x = −xmin/(xmax−xmin)` (same for y).

Skipping calibration (`setup.sh` → answer `n`) uses the default matrix in `defaults.env`, measured on an MHS35 unit. Resistive panels vary between units; measuring is recommended.

Note: on some builds `libinput debug-events` prints pre-calibration coordinates even when a matrix is active. Verify with `sudo libinput list-devices` — digits on the `Calibration:` line (rather than `identity matrix`) mean the matrix is applied.

## How it works

| Layer | This repo | LCD-show |
|---|---|---|
| Kernel | DRM/KMS — panel is a DRM connector | `fbtft` → `/dev/fb1` framebuffer |
| Pixel path | Compositor renders to the panel directly | `fbcp` copies the HDMI framebuffer to `/dev/fb1` via DispmanX |
| Display server | Wayland (labwc/Wayfire) | X11 only |
| Pi 5 | Works | DispmanX removed; panel stays dark |

LCD-show forces X11, disables KMS, and pins HDMI at 480×320 because its design is to copy the HDMI framebuffer to the SPI panel. The DRM path requires none of that.

## Limitations

- The panel sustains roughly 15–25 FPS over SPI at 32 MHz. This is the bus bandwidth limit. Suitable for status displays and controls, not video.
- Touch accuracy on a 3.5" resistive panel is limited by tap-target size at scale 0.75, SPI latency, and parallax from the gap between touch layer and LCD. If taps land off-target after calibration, try `OUTPUT_SCALE=1` (or 0.85–0.9) in `defaults.env` and re-run `sudo steps/04-persist.sh` (this keeps your measured calibration).
- Rotation/scale persistence targets labwc (Trixie's compositor). On Bookworm/Wayfire, add the same `wlr-randr` line to Wayfire's autostart instead.
- Only the default rotation (`90`) has been verified on hardware. `0`, `180` and `270` rotate the display by offsetting the compositor transform, but touch input is not re-mapped, so taps will likely land in the wrong place at those rotations. To set a transform directly: `sudo OUTPUT_TRANSFORM_OVERRIDE=<0|90|180|270> steps/04-persist.sh` (this is also saved for later runs).
- Tested on one MHS35 unit on a Pi 5 / Trixie. Other panels in the table share the pinout but have not been verified — issue reports welcome.

## Troubleshooting

- `systemctl get-default` is authoritative for whether the system boots to a display manager. `raspi-config nonint get_boot_cli` checks a different marker and can disagree.
- `rpi-connect status` reporting `Screen sharing: allowed` only confirms a session file exists. `rpi-connect-wayvnc.service` restarting every ~5 s in the journal means no Wayland compositor is running ([Raspberry Pi Connect docs](https://www.raspberrypi.com/documentation/services/connect.html)).
- A `~/.bash_profile` you did not create suppresses `~/.bashrc`/`~/.profile` in login shells, removing user PATH entries.
- `ps -eo tty,pid,cmd | awk '$1=="tty1"'` shows any display session running outside the display manager.
- The `piscreen` overlay includes its own touch controller. A separate `dtoverlay=ads7846` line conflicts on the SPI chipselect and pen IRQ, and both fail to probe.

Full reference: [docs/lcd-show-issues.md](docs/lcd-show-issues.md).

## Acknowledgements

This repo packages other people's work more than it invents anything:

- **The Raspberry Pi kernel and firmware teams** wrote the actual driver: the [`piscreen` overlay](https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README) and its DRM panel support in the [Raspberry Pi Linux kernel](https://github.com/raspberrypi/linux). `files/config.txt.stock` is the stock Raspberry Pi OS `config.txt` template, reproduced for recovery purposes.
- **[goodtft/LCD-show](https://github.com/goodtft/LCD-show)** and the [lcdwiki](http://www.lcdwiki.com/) projects made these panels usable on earlier Pi generations, and their command naming (`MHS35-show`, `LCD35-show`, `rotate.sh`, `LCD-hdmi`) is mirrored here so their users can find the equivalent commands. No code is reused from them.
- **[libinput](https://wayland.freedesktop.org/libinput/doc/latest/)** (touch calibration), **[systemd hwdb](https://www.freedesktop.org/software/systemd/man/latest/hwdb.html)** (calibration persistence), and **[wlr-randr](https://gitlab.freedesktop.org/emersion/wlr-randr)** (output configuration) do the heavy lifting at runtime.

## References

- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — OS flashing
- [Raspberry Pi getting-started guide](https://www.raspberrypi.com/documentation/computers/getting-started.html)
- [config.txt documentation](https://www.raspberrypi.com/documentation/computers/config_txt.html)
- [Device tree overlays README](https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README) — includes `piscreen` parameters
- [libinput: calibration of absolute devices](https://wayland.freedesktop.org/libinput/doc/latest/absolute-axes.html#calibration-of-absolute-devices)
- [systemd hwdb](https://www.freedesktop.org/software/systemd/man/latest/hwdb.html)
- [wlr-randr](https://gitlab.freedesktop.org/emersion/wlr-randr)
- [goodtft/LCD-show](https://github.com/goodtft/LCD-show) — the legacy installer this replaces
- [lcdwiki: MHS-3.5inch RPi Display](http://www.lcdwiki.com/MHS-3.5inch_RPi_Display), [3.5inch RPi Display](http://www.lcdwiki.com/3.5inch_RPi_Display) — panel hardware documentation

## License

[MIT](LICENSE)
