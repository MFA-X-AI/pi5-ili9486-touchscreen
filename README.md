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

   Touch calibration also uses `chromium` and `python3`, which the desktop image already includes.

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

The second run calibrates touch: a page with red crosshairs opens on the panel, and you tap the centre of each cross, 10 taps in all (see [Touch calibration](#touch-calibration)). Run it with the desktop showing on the panel. After logging out and back in (or rebooting), the panel is a second monitor: landscape, scaled, calibrated touch, a usable refresh rate, all persisted across reboots.

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

If you already ran an LCD-show installer and the system is misbehaving (console boot, 480×320 HDMI, missing PATH entries, or every `apt install` failing with unmet dependencies):

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
| Refresh rate, rotation, scale | `~/.config/labwc/autostart` | [`wlr-randr`](https://gitlab.freedesktop.org/emersion/wlr-randr)` --output SPI-1 --custom-mode 320x480@30Hz --transform 270 --scale 0.75 &` (see [Refresh rate](#refresh-rate)) |
| Touch → panel mapping | `~/.config/labwc/rc.xml` ([docs](https://labwc.github.io/labwc-config.5.html#touch)) | `<touch deviceName="ADS7846 Touchscreen" mapToOutput="SPI-1" />`, so touch stays on the panel when HDMI is also connected |

Every file touched is backed up first (`*.bak-<timestamp>`), all inserted blocks are marker-delimited, and the scripts are idempotent. `./uninstall.sh` removes all of them.

Tunables (rotation, mode, scale, SPI speed, default calibration matrix) are in [`defaults.env`](defaults.env).

## Touch calibration

`sudo steps/03-calibrate-touch.sh` opens a full-screen page on the panel with a red crosshair at 5 known positions (four near the corners, one in the centre) and reads your taps from `libinput debug-events`. It shows the 5 crosshairs twice:

1. **Calibrate.** The first 5 taps are fitted to a full affine matrix (all 6 terms) by [`lib/touch_fit.py`](lib/touch_fit.py), using least squares.
2. **Check.** The second 5 taps are used to measure that matrix. Below about 2.5% of the screen (≈ 10 px) rms is good; above that, run it again.

The result appears on the panel, with each check target and a dot where your tap lands under the new matrix, and in the terminal, with per-tap errors. Tap the panel once more to close it.

Tap with a stylus (touch pen): it's a resistive panel, and a fingertip's contact area is too broad to hit the centre of a cross. The matrix goes to `calibration.env`, and `steps/04-persist.sh` installs it.

Skipping calibration (`setup.sh` → answer `n`) uses the default matrix in `defaults.env`, measured on one MHS35 unit with the default rotation. Resistive panels vary between units; measuring is recommended.

### Why a full fit: the touch axes can be swapped

On the MHS35 this was tested on, an uncorrected panel has **touch mirrored across the diagonal**: tapping top-left registers at bottom-right and vice versa, while top-right and bottom-left are roughly right, so taps near the middle seem only "a bit off". The `piscreen` overlay's `rotate=90` sets `touchscreen-swapped-x-y` on the touch controller. For this panel that flips the touch the other way round from the display, and combined with the compositor's rotation it produces a mirror image.

A mirror can't be fixed by scale and offset alone (a diagonal matrix). It needs the off-diagonal terms, which is why the fit uses all 6, e.g. the default `0.00271 1.12558 -0.04919 1.11325 0.00444 -0.06729`. A loaded matrix is also no proof the matrix is right, so the check round measures where taps actually land: on the test unit, 0.73% of the screen (~3 px) rms.

### How the coordinates fit together

- **`libinput debug-events` prints raw positions**: in % of the touch device, *before* any installed matrix is applied (verified on Trixie). So calibrating doesn't depend on whatever matrix is installed, and the fitted matrix replaces it outright. If you fit by hand, don't multiply the result onto the installed matrix: that counts it twice, which shows up as every corner landing too far outwards.
- **The matrix maps raw touch to the panel's native (unrotated) output.** labwc then applies the output transform (`--transform 270`) to touch, the same as to the picture. The fit converts each target from screen to native coordinates for the current transform. Because of that, changing the compositor rotation later (`rotate.sh`) should not need recalibrating.
- `sudo libinput list-devices` shows the active matrix on the `Calibration:` line. Digits there (rather than `identity matrix`) mean the hwdb matrix is applied. libinput reads it when the device is opened, so log out/in or reboot after changing it.

## Refresh rate

The `ili9486` driver doesn't report a real refresh rate. `wlr-randr` shows a placeholder: `320x480 px, 0.007000 Hz`. Applications that pace their drawing by the refresh rate take it literally: **Chromium draws about once per second**, so every animation runs at ~1 fps.

`steps/04-persist.sh` therefore sets a real mode, `--custom-mode 320x480@30Hz` (`OUTPUT_MODE` in `defaults.env`). Measured with a `requestAnimationFrame` test page in Chromium at 480×320:

| Output mode | Full-screen repaint | Small moving element | Idle |
|---|---|---|---|
| Driver default (0.007 Hz) | 0.8 fps | 0.9 fps | 0.9 fps |
| `--custom-mode 320x480@30Hz` | **10.7 fps** | **26.7 fps** | 28.7 fps |

Chromium's `--disable-gpu-vsync --disable-frame-rate-limit` flags are not a fix: they make it redraw thousands of times per second, which spins the CPU (and heats the Pi) without the panel showing any more.

10.7 fps for a full repaint is the bus limit: a 480×320 frame at 16 bits per pixel is ~2.5 Mbit, and 32 MHz SPI moves about 13 of those per second before overhead. Only the changed region is sent, so small updates (a progress bar, a button highlight) get close to the 30 Hz pace. For smooth-looking UI on this panel, animate small regions rather than the whole screen.

## How it works

| Layer | This repo | LCD-show |
|---|---|---|
| Kernel | DRM/KMS — panel is a DRM connector | `fbtft` → `/dev/fb1` framebuffer |
| Pixel path | Compositor renders to the panel directly | `fbcp` copies the HDMI framebuffer to `/dev/fb1` via DispmanX |
| Display server | Wayland (labwc/Wayfire) | X11 only |
| Pi 5 | Works | DispmanX removed; panel stays dark |

LCD-show forces X11, disables KMS, and pins HDMI at 480×320 because its design is to copy the HDMI framebuffer to the SPI panel. The DRM path requires none of that.

## Limitations

- Full-screen repaints top out at about 11 fps over SPI at 32 MHz; small changes reach close to 30 fps (see [Refresh rate](#refresh-rate)). Suitable for status displays, controls and kiosk UIs, not video.
- If taps land clearly in the wrong place (especially mirrored: top-left registering bottom-right), the matrix is wrong. Re-run `sudo steps/03-calibrate-touch.sh`; the check round shows the remaining error. Small leftover offsets on a 3.5" resistive panel come from tap-target size (smaller at scale 0.75) and parallax between the touch layer and the LCD.
- Mode/rotation/scale persistence targets labwc (Trixie's compositor). On Bookworm/Wayfire, add the same `wlr-randr` line to Wayfire's autostart instead.
- Only the default rotation (`90`) has been verified on hardware. `0`, `180` and `270` rotate the display by offsetting the compositor transform. labwc rotates touch input with it, so a calibration from `steps/03-calibrate-touch.sh` should stay valid, but this is untested; re-run calibration if taps land wrong. To set a transform directly: `sudo OUTPUT_TRANSFORM_OVERRIDE=<0|90|180|270> steps/04-persist.sh` (this is also saved for later runs).
- Using the panel for a full-screen Chromium kiosk needs a few extra settings (scale 1, keyring prompt, touch scrolling): see [docs/chromium-kiosk.md](docs/chromium-kiosk.md).
- Tested on one MHS35 unit on a Pi 5 / Trixie (kernel 6.12). Other panels in the table share the pinout but have not been verified — issue reports welcome.

## Troubleshooting

- `systemctl get-default` is authoritative for whether the system boots to a display manager. `raspi-config nonint get_boot_cli` checks a different marker and can disagree.
- `rpi-connect status` reporting `Screen sharing: allowed` only confirms a session file exists. `rpi-connect-wayvnc.service` restarting every ~5 s in the journal means no Wayland compositor is running ([Raspberry Pi Connect docs](https://www.raspberrypi.com/documentation/services/connect.html)).
- A `~/.bash_profile` you did not create suppresses `~/.bashrc`/`~/.profile` in login shells, removing user PATH entries.
- `ps -eo tty,pid,cmd | awk '$1=="tty1"'` shows any display session running outside the display manager.
- The `piscreen` overlay includes its own touch controller. A separate `dtoverlay=ads7846` line conflicts on the SPI chipselect and pen IRQ, and both fail to probe.
- Every `apt install` failing with "unmet dependencies" for `xinput-calibrator:armhf` / `xserver-xorg-input-evdev:armhf` is LCD-show residue: the installer force-installs 32-bit `.deb`s that can never finish installing on a 64-bit system. `recover-from-lcd-show.sh` purges just those two. Avoid `apt --fix-broken install`: it tries to complete them by pulling in a 32-bit library stack and core upgrades (libc6, systemd, udev).
- Animations in a browser crawling at ~1 fps: the output is still on the driver's 0.007 Hz placeholder mode (`wlr-randr` shows it). See [Refresh rate](#refresh-rate).

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
