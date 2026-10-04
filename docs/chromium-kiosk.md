# Running a full-screen Chromium kiosk on the panel

Notes from running a web app full-screen on an MHS35 (Pi 5, Trixie, labwc) with
the panel as the only display. Everything in the main README still applies;
these are the extra settings a browser kiosk needs.

## Starting it

In `~/.config/labwc/autostart`, after this repo's `wlr-randr` block:

```sh
sleep 4 && wlr-randr --output SPI-1 --scale 1 && chromium --kiosk --password-store=basic --ozone-platform=wayland --app=http://localhost:8080/ --noerrdialogs --disable-infobars &
```

- The binary is `chromium` on Trixie. `chromium-browser` (Bookworm and older
  guides) does not exist there, and an autostart line calling it silently
  never starts.
- Keep the whole kiosk on one line of its own, so deleting that line restores
  the normal desktop exactly.

## Use scale 1, not 0.75

With the desktop at `--scale 0.75`, the logical screen is 640×427. Chromium
sizes its window from the physical 480×320, so the kiosk covers only the
top-left three quarters of the screen. `--window-size=480,320` gives the same
result, and kiosk mode does not override it. Chromium also remembers that
size in its profile (`window_placement` in `Default/Preferences`).

Chromium only reads the scale at start-up, so changing it while running
leaves the page laid out wrong. Set `--scale 1` *before* starting Chromium,
as in the line above. At scale 1, 1 CSS px = 1 panel pixel, and a page designed
for 480×320 fits exactly.

## Keyring prompt on autologin

On first start, Chromium asks the desktop keyring (gnome-keyring) for a
place to store its encryption key. With autologin, no login password ever
unlocks a keyring, so a "Choose password for new keyring" dialog appears over
the kiosk. Cancelling it only lasts until the next boot.

`--password-store=basic` makes Chromium use its own built-in store and never
ask for the keyring. The trade-off is that anything it saves is protected
only by a fixed key, which doesn't matter for a kiosk with no logins.

## Refresh rate

Without this repo's 30 Hz mode, Chromium draws about once per second on
this panel. See the README's "Refresh rate" section.

## Swipe to scroll

labwc's default touch handling (`mouseEmulation="yes"` on the `<touch>`
entry in `rc.xml`) turns touches into mouse events. A mouse drag in Chromium
selects text instead of scrolling, so swipe-to-scroll doesn't work.
Setting `mouseEmulation="no"` should pass real touch events through, so swipes
scroll natively. **Not yet tested on hardware.**

## Microphone (if the app records)

- `--use-fake-ui-for-media-stream` auto-approves the microphone prompt. The
  real microphone is still used.
- Chromium records through PipeWire's PulseAudio interface, so a USB mic set as
  PipeWire's default source (`wpctl set-default <id>`) works even when plain
  ALSA tools don't. Without the `pipewire-alsa` package, `arecord`'s
  `default` device is HDMI card 0, which can't record ("capture slave is not
  defined"). Test the mic directly with
  `arecord -D plughw:CARD=<card>,DEV=0 ...`, or install `pipewire-alsa`.

## Getting back to the desktop

- Until the next boot: Alt+F4 with a keyboard (or kill the Chromium process
  started with your `--app=` URL), then put the scale back with `wlr-randr
  --output SPI-1 --scale 0.75`.
- Permanently: delete the kiosk line from the autostart and reboot.
