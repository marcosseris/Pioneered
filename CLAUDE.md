# Pioneered: how this project works

Pioneered turns a Raspberry Pi 4B, a touch screen and a Pioneer DDJ-400
into a standalone XDJ-style DJ console: boot the Pi, plug in rekordbox USB
sticks, and DJ without a laptop. It has three layers, all in this repo:

1. **The skin** (repo root): a Mixxx legacy XML skin, installed to
   `~/.mixxx/skins/Pioneered` on the Pi.
2. **Patched Mixxx** (`mixxx-patch/`): a series of source patches applied on
   top of Debian trixie's `mixxx_2.5.0+dfsg-3`. CI builds them into arm64
   `.deb`s that are attached to every GitHub release.
3. **The Pi layer** (`pi/`): shell scripts, systemd units, udev rules and
   ALSA config installed on the Pi itself. They handle USB auto-mount, the
   updater, the Mixxx watchdog and LedFx room lights.

The fork lives at **github.com/marcosseris/Pioneered**. It used to be called
`ogg755/Pioneered`, and GitHub still redirects the old name, which is the
`origin` URL in some checkouts. Upstream is `timewasternl/Pioneered`, and
you cannot push to it. Work on `master`.

## The hardware and the Pi

- Pi 4B, 2 GB RAM, Raspberry Pi OS 64-bit **trixie**. User `rpims`, host
  `xdj400.local` (mDNS can drop out, so use the IP from `hostname -I` with
  `-o HostKeyAlias=xdj400.local`). SSH key auth works from the dev PC.
  `sudo` is passwordless for `rpims`.
- Boot path: getty autologin on tty1, then `~/.profile` runs `startx`, then
  Openbox runs `~/.config/openbox/autostart`, which starts Mixxx (a bare
  `mixxx &`, or `/usr/local/bin/mixxx-watchdog.sh &` once the r43+ updater
  has rewritten the line). The desktop does **not** wait for
  `multi-user.target`, so a slow systemd unit does not delay Mixxx.
- Audio: the DDJ-400 is the sound card (Master on ch 1-2, Headphones on ch
  3-4) and must be the clock reference. ALSA loopback `snd-aloop` is pinned
  to card 10 (`Loopback`) for LedFx. Mixxx opens devices by `hw:N` number,
  so card numbers must not move. Mixxx's sound config is in
  `~/.mixxx/soundconfig.xml`.
- Mixxx packages are `apt-mark hold`. The journal is not persistent, so
  only the current boot's journal exists. Mixxx's log is
  `~/.mixxx/mixxx.log` (rotated `.1`..`.10`). It is buffered: a log that
  ends abruptly does **not** show where Mixxx hung or died.

## Skin (repo root)

- `skin.xml` is the root. The top-level pages and panels are `deck.xml`,
  `library.xml`, `search.xml`, `rmx.xml`, `settings.xml`, `wifi.xml`,
  `update.xml`, `topbar.xml` and so on. Shared pieces are in `templates/`
  (`decks_row.xml`, `toggle_button.xml`, `settings_scrim.xml`, ...).
  `style.qss` holds the Qt stylesheet.
- Banners (USB, load-blocked, ...) are full-screen groups in a
  `<Layout>stacked</Layout>` overlay at the root of `skin.xml`. In a stacked
  layout the first child is the top one.
- Skin-only state uses `[Skin],...` controls created by manifest attributes
  (`show_settings`, `show_keyboard`). Anything the skin cannot do on its
  own is a C++ control under `[Library],...` or `[Pioneered],...` that a
  patch adds.
- Skin-only changes need no rebuild. The updater copies the skin from the
  release tag's source tarball.

## Patched Mixxx (`mixxx-patch/`)

- Each `*.patch` is a quilt-style patch (`patch -p1`) with a `Description:`
  header that explains the why. Read it before you change the patch.
- **The order matters.** CI applies the patches in the order listed in
  **both** `.github/workflows/build-mixxx-deb.yml` and
  `.github/workflows/publish-release.yml`. A new patch must go at the end
  of the list in both files, or the release build will not contain it.
- `mixxx-patch/VERSION.md` is the changelog of the patch series and the
  facts about the build environment.
- To make or change a patch, get the source (`apt-get source mixxx` on
  trixie, or the Debian pool) and apply every patch in CI order. Copy the
  files you will edit to a baseline directory, edit the tree, then
  `git diff --no-index baseline tree`, rewriting the paths to `a/` and
  `b/`. Check the result with `patch -p1 --dry-run` against the baseline.
  The tree files use LF line endings. A one-line change inside a hunk that
  adds a new file (lines starting with `+` only) can be edited in the
  `.patch` directly, because the line counts do not change.
- Mixxx 2.6 git (`Code\mixxx` on the dev PC, when present) is useful for
  upstream backports. Tag `2.5.0` gives the baseline of a file.
- Things to remember about the code:
  - Never block the GUI thread. Every external command (nmcli, systemctl,
    sudo, the updater) runs through an **async** `QProcess` with
    `finished` and `errorOccurred` handlers. Sudo calls use `-n`, because
    no terminal is there to answer a password prompt.
  - Most of the Pi integration controls live in `LibraryControl`
    (`src/library/librarycontrol.{h,cpp}`): the settings menu, Wi-Fi,
    update, LEDS, jog sensitivity, power off and restart.

## Pi layer (`pi/`)

| File | Installed to | Purpose |
|---|---|---|
| `update-pioneered.sh` | `/usr/local/bin/` | One-shot updater: fetches the latest release's debs and skin, installs them, refreshes the files below, then reboots (`--no-reboot` for the Settings UPDATE button) |
| `usb-mount.sh`, `usb-umount.sh`, `usb-mount@.service`, `99-usb-automount.rules` | `/usr/local/bin`, systemd, udev | Mounts USB sticks at `/media/USBA` and `/media/USBB` |
| `mixxx-watchdog.sh` | `/usr/local/bin/` | Relaunches Mixxx if it crashes (started from the Openbox autostart) |
| `ledfx-install.sh` | run by hand once | Installs LedFx in `/opt/ledfx`, snd-aloop, the `ledfx_in` PCM, the service and the sudoers rule |
| `ledfx.service` | `/etc/systemd/system/` | LedFx (web UI on :8888), niced and pinned to core 3. **Not enabled at boot**: the LEDS button starts it |
| `ledfx-alsa.conf` | `/etc/alsa/conf.d/60-ledfx.conf` | `ledfx_in`: holds the loopback at 2 ch / 44.1 kHz and downmixes for LedFx |
| `ledfx-snd-aloop.conf` | `/etc/modprobe.d/` | snd-aloop as card 10 |
| `audio-diag.sh` | ad hoc | Headphone distortion diagnostics |
| (written by the updater) | `/etc/X11/xorg.conf.d/10-blanking.conf` | Loads X DPMS with every X timer at 0, so only Mixxx's screen sleep powers the display down |

The updater re-installs everything in `pi/` that has to stay in step with a
release. If a change to `pi/` must reach existing units, add it to
`update-pioneered.sh`. The updater installs *itself* through a temp file
and a rename, because bash reads a running script as it goes. Changes to
the updater therefore only take effect on the **second** update run.

### Screen sleep (`screen-sleep.patch`)

`mixxx::ScreenSleep` (`src/util/screensleep.{h,cpp}`) switches the display
off after `[Pioneered] ScreenSleepMinutes` (mixxx.cfg, default 5, 0 = never)
with no touch, key, controller input or playing deck. Any input wakes it,
and the waking touch is swallowed. Display control is `xset dpms force
off|on`, with a fallback to `xset s activate` blanking. raspi-config's
"screen blanking off" setting disables the X DPMS extension
(`10-blanking.conf`), so the updater rewrites that file. Check the result
with `xset q` (should say "DPMS is Enabled", timers 0) and
`cat /sys/class/drm/card0-HDMI-A-1/dpms`. The DDJ-400 sends no MIDI while
untouched; if a future controller does, the screen will never sleep.

### Room LEDs (LedFx)

Mixxx's Booth output (`Loopback: PCM (hw:10,0)`, ch 1-2) goes into the
ALSA loopback. LedFx captures it through `ledfx_in` and drives WLED strips
over the LAN. The LEDS button in Settings (`ledfx-status.patch`) runs
`sudo -n systemctl start|stop ledfx`. It is green when the service is
active and NetworkManager reports `full` or `limited` connectivity. It is
polled only while the settings panel is open.

Rules learned the hard way:
- LedFx is **off at boot**. It starts only from the LEDS button.
- `ledfx.service` must not depend on `network-online.target`. Its start
  job would then wait for NetworkManager-wait-online. That wait is capped
  at 60 s, though in tests with no known network it gave up after about
  8 s.
- Never point LedFx at the raw `hw:10,x` devices. snd-aloop locks the
  second opener to the first one's parameters, LedFx opens mono, and
  Mixxx's 2-channel Booth then fails with "invalid number of channels".
  Use `ALSA: ledfx_in`.
- LedFx saves its audio device as a PortAudio *index*, and the indexes
  change with which cards are present or busy. If you see
  `device_index_validator: val=N not in valid indexes`, LedFx has fallen
  back to some other device.

## Releases (how the user updates)

1. Add `docs/release-notes/v2.5.0-rNN.md`, written for the user (what
   changed, how to install). Put the marker line `<!-- debs: rebuild -->`
   in it whenever anything in `mixxx-patch/` changed. Without the marker,
   the previous release's debs are re-attached, which is correct only for
   skin-only or `pi/`-only releases.
2. Commit, then `git tag v2.5.0-rNN` and push both master and the tag.
   `publish-release.yml` builds the debs (about 1 h on `ubuntu-24.04-arm`)
   and publishes the release with the three debs attached. A tag without a
   notes file is ignored.
3. On the Pi: Cog → SOFTWARE UPDATE → UPDATE (tap twice), or
   `sudo update-pioneered.sh`.

`gh` is at `C:\Program Files\GitHub CLI\gh.exe` (not on PATH). When you run
`build-mixxx-deb.yml` by hand, always pass `--ref master`. Commits end with
the `Co-Authored-By` trailer.

## Debugging on the Pi

- `journalctl -b`, `journalctl -u ledfx`, `journalctl -t mixxx-watchdog`,
  and `coredumpctl list mixxx` (with the `mixxx-dbgsym` deb installed).
- `systemd-analyze critical-chain` shows what boot waits for.
- To test "no Wi-Fi at a venue", switch off autoconnect on the saved Wi-Fi
  profiles (`nmcli con mod <name> connection.autoconnect no`) and reboot.
  Turning the radio off is not the same: NetworkManager then reports no
  network at once, instead of trying for 60 s.
- A Mixxx thread's state is in
  `ps -L -o tid,stat,wchan:32,comm -p $(pgrep -x mixxx)`. A main thread
  sitting in `poll_schedule_timeout` is idle in the Qt event loop, which
  means the GUI is responsive.
