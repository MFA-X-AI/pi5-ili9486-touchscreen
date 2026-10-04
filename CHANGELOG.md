# Changelog

The README and docs always describe the current state; history lives here.

## 2026-10-04

### Changed
- **Touch calibration uses on-screen crosshairs and a full affine fit.**
  - `steps/03-calibrate-touch.sh` shows 5 crosshairs on the panel twice (calibrate, then check), fits all 6
    matrix terms (`lib/touch_fit.py`), and reports the check-round error on the panel and in the terminal.
  - The previous 4-corner method fitted scale and offset only. It could not correct the MHS35's swapped touch
    axes, so taps landed mirrored across the diagonal: 66% rms error, against 0.73% (~3 px) for the new fit on
    the same unit.
- Default `CAL_MATRIX` replaced with one fitted by the new method (`0.00271 1.12558 -0.04919 1.11325 0.00444
  -0.06729`). The previous default mirrored taps.
- Docs: `libinput debug-events` prints raw (pre-calibration) coordinates. This was verified on Trixie,
  where the docs had previously said "on some builds".
- Docs: full-screen repaint rate corrected to ~10.7 fps (measured), from "15–25 FPS".
- `rotate.sh` / README: labwc applies the output transform to touch, so a calibration stays valid across
  compositor rotations (expected; only 90 verified).

### Added
- `OUTPUT_MODE=320x480@30Hz` (`--custom-mode` in the labwc autostart). The `ili9486` driver reports a 0.007 Hz
  placeholder refresh, which held Chromium to ~1 fps.
- `recover-from-lcd-show.sh` purges the half-installed `xinput-calibrator:armhf` and
  `xserver-xorg-input-evdev:armhf` that LCD-show force-installs, which block every `apt install`.
- `doctor.sh`: checks for the placeholder refresh rate and the half-installed armhf packages.
- `docs/chromium-kiosk.md`: running a full-screen Chromium kiosk on the panel (scale 1, keyring prompt,
  refresh, touch scrolling, microphone).
- `.gitattributes`: LF for the extensionless wrapper scripts and `*.py`, so Windows checkouts copied to a Pi
  still run.

## 2026-07-18

- Initial release: `piscreen,drm` overlay setup, 4-corner touch calibration, rotation/scale persistence for
  labwc, LCD-show recovery, `doctor.sh`, LCD-show-compatible command names.
