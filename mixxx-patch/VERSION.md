# Pi Mixxx build facts (source of truth for the patch + CI)

- Installed package: mixxx 2.5.0 (Debian source package `mixxx_2.5.0+dfsg-3`; arm64 binary in the archive is the binNMU `2.5.0+dfsg-3+b1`)
- OS: Raspberry Pi OS 64-bit, Debian codename: trixie
- Arch: arm64
- Source pool: http://deb.debian.org/debian/pool/main/m/mixxx/
  - Files: `mixxx_2.5.0+dfsg-3.dsc`, `mixxx_2.5.0+dfsg.orig.tar.xz`, `mixxx_2.5.0+dfsg-3.debian.tar.xz` (SHA256 of both tarballs verified against the .dsc)
- Package origin: Debian archive (deb.debian.org), not the Raspberry Pi archive — Raspberry Pi OS arm64 pulls `mixxx` from Debian; archive.raspberrypi.com does not carry it.
- Debian packaging patches (`debian/patches/series`): `0001-disable_soundsourcem4a.patch`, `0002-desktop_file.patch`, `0004-remove_inappropriate_arm_flags.patch`, `0005-disable_soundproxy_test.patch` — **none touch `src/library`**, so our patch applies cleanly on top of them.
- Source tree verified after extraction (in `..\mixxx-src\mixxx-2.5.0`): `src/library/librarycontrol.cpp`, `src/library/librarycontrol.h`, `src/library/library.h` all present.
- Queried: 2026-07-08

> **Caveat:** Installed version 2.5.0 confirmed by user (SSH to the Pi was
> unavailable); Debian codename **trixie** inferred from archive contents —
> packages.debian.org/trixie/mixxx shows `2.5.0+dfsg-3`, and it is the only
> Debian release shipping a 2.5.0 build (bookworm has 2.3.3, sid/forky have
> 2.5.6). **Re-verify with `apt policy mixxx` on the Pi at deploy time
> (Task 7) before installing the built .deb.**

## Patch series (applied in this order by CI)

1. `usb-browse.patch` — touch browse + hold-to-eject (field-verified r8.1)
2. `pdb-corruption-hardening.patch` — PDB segfault fixes (field-verified r8.1)
3. `xdj-behavior.patch` — waveform EQ decoupling, loop from cue, Filter curve
   (shipped r9.1, awaiting field test). r23 (2026-08-14) also pins the overall
   waveform amplitude: `WaveformWidgetRenderer::onPreRender` sets `m_gain = 1.0`
   instead of reading `[ChannelN],total_gain`, so the channel gain/trim knob and
   replaygain no longer scale the waveform height — it is drawn at a fixed scale
   reflecting the track's content, like Pioneer hardware. total_gain still drives
   the audio path; the /2 EnginePregain compensation via `getGain()` is retained.
   Touches `src/waveform/renderers/waveformwidgetrenderer.cpp`.
4. `library-ui.patch` (added 2026-07-11) — "Tracks visible in list" zoom
   preference (`[Library] VisibleRows`, default 8), rekordbox lists always
   open sorted by # ascending, Pioneer-style key traffic light vs the master
   deck (master = playing deck that started most recently; green = Camelot
   compatible; keys shown as note names), fixed rekordbox column set
   (#, Title, Artist, Key, Duration) with proportional widths filling the
   viewport (r13).
5. `xdj-hardware.patch` (added 2026-07-11, r14) — rekordbox-style red bar
   markers on the waveform beatgrid (importer anchors the grid on the first
   beat numbered "1"); controller auto-reconnect watchdog (PortMidi error
   counting + 5 s rescan/reopen of enabled devices, incl. plug-in after
   startup); DDJ-400 mapping jumps deck tempo to the physical fader position
   on track load (200 ms after load, then soft takeover resumes).
6. `search-osk.patch` (added 2026-07-12) — track Search tab replacing the
   Sampler tab. Adds `WSearchLineEdit::slotSetSearchText()` (sets text and
   re-runs the search, which `slotRestoreSearch()` does not) and
   `[Library],search_key_a..z` / `search_key_0..9` / `search_space` /
   `search_backspace` push controls, so the skin's on-screen QWERTY keyboard
   drives the native search box over the selected folder. Clearing reuses the
   existing `[Library],clear_search`. Touches `src/widget/wsearchlineedit.{h,cpp}`
   and `src/library/librarycontrol.{h,cpp}`.
7. `usb-force-eject.patch` (added 2026-07-12) — two-tier USB hold: at 5s a
   locked stick shows the explanatory banner and the hold continues; at 10s
   playing decks on that stick are stopped and the eject runs regardless.
   Also adds `[Library],load_blocked`, set by WTrackTableView when a load is
   silently rejected because the target deck is playing (skin shows
   "PAUSE DECK TO LOAD"). Touches `src/library/librarycontrol.{h,cpp}`,
   `src/widget/wtracktableview.cpp`.
8. `rekordbox-import-fixes.patch` (added 2026-07-17) — two upstream backports:
   (a) ANLZ cue/loop comments decoded as UTF-16**BE** (they were decoded LE,
   turning ASCII labels into CJK mojibake on the waveform; upstream
   d96cae92ca, fixes mixxx#14789); (b) PDB page header's row count is really
   a 13-bit `num_rows` + 11-bit `num_rows_valid` bitfield — the old
   `num_rows_small`/`num_rows_large` heuristic undercounted rows on pages
   with many small rows, so playlists imported with most/all entries missing
   (upstream 2144bf9075, PR mixxx#15745). Touches
   `src/library/rekordbox/rekordboxfeature.cpp`,
   `lib/rekordbox-metadata/rekordbox_pdb.{cpp,h}`.
9. `banner-overlay-transparency.patch` (added 2026-07-19, r20) — skin parser
   gains an optional `<TransparentForMouseEvents>true</...>` node on any
   widget, setting `Qt::WA_TransparentForMouseEvents`. The full-screen popup
   banner overlays use it so that showing a banner over the held USB button
   no longer sends the button a Leave event (WPushButton fakes a mouse
   release on Leave, which cancelled the 5-10s force-eject hold), and so
   visible banners don't swallow touches. Also bumps the banner clear timer
   2s -> 3s for readability. Touches `src/skin/legacy/legacyskinparser.cpp`,
   `src/library/librarycontrol.cpp`.
10. `headphone-gain-ceiling.patch` (added 2026-07-19) — raises the cue/PFL
    headphone gain ceiling from +14 dB to +30 dB (`[Master],headGain`). The
    DDJ-400 cue out (ch 3-4) maxed out far too quiet on the Pi; an aplay
    -6 dBFS bypass tone straight to hw ch 3-4 (Mixxx out of the loop) was
    loud and clean, exonerating the DAC/ALSA/format/PortAudio path and
    proving ~20 dB of clean headroom the +14 dB stage could not reach.
    Audio-taper pot, so unity stays at knob centre; only the top extends.
    Touches `src/engine/enginemixer.cpp`. If the physical HEADPHONES LEVEL
    knob is re-mapped to headGain, scale it to the new x31.6 max.
11. `hold-to-restart.patch` (added 2026-07-19) — keyboard-free recovery:
    holding either on-screen LOAD button for 7 s restarts Mixxx. The skin's
    LOAD buttons press `[Library],restart_hold_1/2` alongside
    `LoadSelectedTrack` (which still loads on press, unchanged);
    `LibraryControl` runs the hold with the same accelerating 250→80 ms
    flash as the USB eject hold (display control `[Library],load_flash_1/2`,
    0 normal / 1 flash-white), shows a `[Library],restarting` banner
    ("RESTARTING MIXXX…"), then `QProcess::startDetached`s a `/bin/sh`
    helper that survives the kill: `killall mixxx` (SIGTERM, clean library
    flush), up to 10 s wait, `killall -9` fallback, then relaunches with
    the original binary path + argv (quoted), exporting `DISPLAY=:0` if
    unset. Releasing before 7 s cancels; the first 600 ms never flash so
    normal load taps don't flicker. Only recovers *soft* hangs — if the Qt
    event loop is fully wedged the button can't fire (an external watchdog
    would be needed for that). Touches `src/library/librarycontrol.{h,cpp}`.
    Skin side (same release): `templates/load_button.xml` (2 states + new
    connections), `style.qss` (white flash + banner style), `skin.xml`
    (RestartingBanner overlay).
12. `system-menu.patch` (added 2026-08-04) — on-screen settings menu behind a
    cog in the topbar. `LibraryControl` gains `[Library],menu_power`,
    `menu_restart`, `menu_disarm` (push, 1 on press / 0 on release) and the
    display controls `arm_power` / `arm_restart`, which drive the skin's red
    "TAP AGAIN TO …" button faces. First press arms, second commits; arming
    one option disarms the other, BACK and the cog press `menu_disarm`, and a
    5 s single-shot timer disarms both so a menu left open never leaves a live
    one-tap kill on screen. Restart reuses `triggerRestart()` from
    `hold-to-restart.patch` — one implementation, two entry points. Power off
    runs `systemctl poweroff || sudo -n poweroff || sudo -n shutdown -h now`
    via `QProcess` (logind/polkit normally grants a local session this with no
    sudo rule; the fallback is the same passwordless sudo the USB eject uses),
    showing `[Library],powering_off` and, if every route is refused,
    `power_off_failed`. Note `systemctl` returns 0 as soon as the job is
    queued, so exit 0 means "accepted", not "finished". Touches
    `src/library/librarycontrol.{h,cpp}`.
    Skin side (same release): new `settings.xml` panel template, `topbar.xml`
    (expanding `TabSpacer` + `SettingsCog`, so the cog pins to the corner and
    the tabs keep their rendered width), `skin.xml` (`SettingsOverlay` — the
    one overlay deliberately *not* `TransparentForMouseEvents`, which is what
    makes it modal — plus the two new banners and the `[Skin],show_settings`
    attribute), `style.qss`.

    Both CI workflows apply the series above. `publish-release.yml` had
    silently drifted, applying only patches 1-9 — releases cut from it shipped
    without the headphone gain ceiling or hold-to-restart. Resynced with
    `build-mixxx-deb.yml` in the same commit as this patch.
13. `perf-render-repaint.patch` (added 2026-08-13) — responsiveness pass over
    the hot paths the patches above introduced. No controls, no config keys,
    no observable behaviour change:
    * Waveform bar markers: the downbeat X list becomes a reused member
      instead of a QVector reallocated on every `draw()`; the two
      `drawPolygon()` calls per downbeat collapse into one reused
      `QPainterPath` filled with a single `drawPath()`; and `it - firstMarker`
      is computed once before the loop rather than per beat —
      `mixxx::Beats::const_iterator` is not guaranteed random-access, so
      `operator-` can degrade to an O(n) `std::distance()`, making that loop
      O(n²) per frame. The allshader/QOpenGL renderer gets the same iterator
      fix plus a `reserve()` on its downbeat vertex buffer.
    * Key traffic light: the refresh emitted `dataChanged` over the whole
      `rowCount() × columnCount()` rectangle on every deck play/pause and
      master-deck track change — i.e. continuously during a mix, through the
      sort/filter proxy, over playlists of thousands of rows. Only the Key
      column is invalidated now.
    * `KeyUtils::guessKeyFromText()` ran once per Key cell per repaint, and a
      second time in `roleValue()` for the displayed note name. Both share a
      memoized text→`ChromaticKey` hash on `XdjMasterKeyTracker`.
    * The visible-rows zoom and the fixed column layout both re-applied their
      derived values from inside `resizeEvent()`, and `setFont()` /
      `setDefaultSectionSize()` / `setColumnWidth()` each relayout the header
      and repaint the viewport. Both early-out when the derived numbers are
      unchanged, with explicit invalidation where the guard cannot see the
      change (a new base font, a newly loaded model).
    * The controller reconnect watchdog rescanned PortMidi + HID every 5 s
      *forever* when a controller was enabled in the preferences but absent.
      The first three attempts stay at 5 s so replugging still reconnects
      promptly, then the interval doubles to a 60 s ceiling and resets once
      everything enabled is open. Touches
      `src/waveform/renderers/waveformrenderbeat.{h,cpp}`,
      `src/waveform/renderers/allshader/waveformrenderbeat.cpp`,
      `src/library/basetracktablemodel.cpp`,
      `src/widget/wlibrarytableview.{h,cpp}`,
      `src/widget/wtracktableview.{h,cpp}`,
      `src/controllers/controllermanager.{h,cpp}`.
14. `usb-browse-one-tap.patch` (added 2026-08-13) — USB A/B navigates on the
    **first** press. The rekordbox device list only refreshes on activation, so
    a press on a freshly inserted stick used to kick off the async
    `QtConcurrent` device scan, return empty-handed, and do nothing visible;
    only a second press found the device. A press that cannot find its device
    now records the slot in `m_pendingUsb` and completes itself from the
    sidebar model's `rowsInserted`/`modelReset` signal when the scan lands. The
    retry deliberately does **not** re-prime the scan (that would restart it on
    every batch of inserted rows); a new press, an eject or a root restore
    supersedes the pending request; a 10 s single-shot timeout drops a request
    for a stick that never appears; and a pending request whose slot is already
    rooted is discarded rather than toggling the sidebar back off.
    Also stops discarding the tap that lands while a PDB parse is in flight —
    `activateChild()` queued behind a running parse used to be dropped with
    only a warning, which on a slow stick is seconds of UI that ignores you.
    The activation is stored as a `QPersistentModelIndex` and re-dispatched
    from `onTracksFound()` through the event loop, taken out of the queue slot
    *before* the future result is unwrapped so a failed parse releases it
    instead of wedging it. Touches `src/library/librarycontrol.{h,cpp}` and
    `src/library/rekordbox/rekordboxfeature.{h,cpp}`.
    Skin side (same release): `style.qss` only — button modernisation
    (consistent 3/4/8px radius tiers, `qlineargradient` fills so buttons read
    as moulded hardware, a dimmed border/inactive-chrome ladder, and a
    `:pressed` face on every button so a touch is acknowledged on touch-down
    instead of when the action lands). The Pioneer palette, the tab strip's
    proportions and the CDJ notch on `#WaveformInfo_Header` are unchanged.
    Note the `:pressed` rules for the USB, LOAD and sampler buttons are scoped
    to `[value="0"]`: a bare `:pressed` stays active for a whole hold and
    would outrank the `[value]` rules that drive the eject and
    hold-to-restart flashes, hiding them.
15. `beatgrid-ticks.patch` (added 2026-08-15, r24) — restyles the rekordbox
    beatgrid overlay from `xdj-hardware.patch` to the Pioneer CDJ/XDJ look.
    Every-beat marks become short ticks at the top and bottom edges instead of
    full-height lines, and the bar-start (downbeat) markers become thin red
    vertical bars top and bottom instead of large red triangles/arrows. Both
    the software (QPainter) and allshader (QOpenGL) renderers are changed in
    lock-step. Software: the top tick stays in `m_beats`, a new `m_beatsBottom`
    holds the bottom tick, and the downbeat `QPainterPath` draws `addRect`
    bars rather than triangles. Allshader: the top tick stays in `m_vertices`
    (so its `reserved`/`DEBUG_ASSERT` vertex count is unchanged), a new
    `m_beatBottomVertices` buffer holds the bottom tick (own draw pass, beat
    colour), and the two downbeat triangles become two rectangles (downbeat
    reserve doubles, 6→12 vertices per bar). Size is controlled by two named
    constants per renderer: `kBeatTickFraction` (tick/bar height as a fraction
    of the waveform height) and `kBarHalfWidth` (red bar half-width, px).
    Applied after `perf-render-repaint.patch`, on top of its batched
    `QPainterPath` / reused-member draw path. Touches
    `src/waveform/renderers/waveformrenderbeat.{h,cpp}` and
    `src/waveform/renderers/allshader/waveformrenderbeat.{h,cpp}`.
16. `jog-nudge.patch` (added 2026-08-17, r25) — two jog wheel nudge fixes on
    the DDJ-400.
    * **The side ring never scratches.** The stock mapping routes all three jog
      rotation messages — side `0x21`, platter `0x22` (vinyl on) and `0x23`
      (vinyl off) — to one `jogTurn()` that scratches whenever
      `[ChannelN],scratch2_enable` is set, with no regard for which part of the
      wheel moved. That flag outlives the touch: `scratchDisable()` does not
      clear it, it starts an alpha-beta ramp back to playback speed and only
      clears the flag once the rate settles within `1e-5` of target — and
      `scratchProcess()` starves that ramp while the wheel keeps moving
      (`m_lastMovement`, refreshed by every `scratchTick()`). So a side nudge
      in that window scratched the deck *and* held the window open, which is
      why it self-healed after a few seconds of leaving the wheel alone.
      `jogTurn()` now scratches only for CC `0x22` and only while the touch
      sensor (note `0x36`) says the platter top is held, tracked in the new
      `PioneerDDJ400.jogTouched` state — set *before* the loop-adjust early
      return, which fires on release as well as press and would otherwise
      strand the flag. A bend arriving while a stale scratch is still active
      calls `scratchDisable(deck, false)` first, so the nudge is not swallowed
      by `scratch2` driving the rate.
    * **Nudge response no longer depends on the audio buffer size.** The jog
      smoothing window was a `Rotary` moving average over a hard-coded 25
      *audio buffers* — ~125 ms at a 5 ms desktop buffer, but well over half a
      second at the Pi's buffer, and being a box filter it kept applying the
      nudge for that whole window after the hand stopped, so every beatmatch
      overcorrected. `RateControl::updateJogFilter()` now sizes the window from
      the real buffer duration (`kJogFilterWindowSeconds` = 60 ms, clamped to
      1..25 buffers) and normalises `jogSensitivity` against a reference
      1024-frame @ 44.1 kHz buffer (correction clamped to 0.5..2.0), so a
      detent shifts the track by the same amount at any latency. Both answer
      upstream `FIXME`s in `ratecontrol.cpp`. Recomputed only when the buffer
      size changes; `Rotary::setFilterLength()` allocates nothing (the vector
      is sized to `kiRotaryFilterMaxLen` in the constructor), and it now also
      clamps `m_iFilterPos` into the shortened window so no sample is written
      past its end. The mapping's `bendScale` — the per-detent sensitivity
      knob, and the one number to retune for feel — drops `0.8` → `0.4`.
    Touches `res/controllers/Pioneer-DDJ-400-script.js`,
    `src/engine/controls/ratecontrol.{h,cpp}`, `src/util/rotary.cpp`.
17. `load-returns-to-overview.patch` (added 2026-08-29, r26) — after a load
    that actually happened, the screen returns to the Overview tab, the way a
    CDJ puts the deck back in front of you once the track is on it. Until now
    every LOAD left you in Browse (or Search) and needed a second tap on the
    Overview tab. `WTrackTableView::loadSelectedTrackToGroup` writes 1 to
    `[Tab],overview` — the skin's WidgetStack trigger for the Overview page,
    the very control the Overview tab button writes, so the Browse/Search
    triggers are cleared by their existing `on_hide_select`. The write sits
    *after* every rejection path in that function, which is the whole point:
    a deck still playing the previous track takes the early return added by
    `usb-force-eject.patch` (raise `[Library],load_blocked`, show "PAUSE DECK
    TO LOAD") and never reaches it, so a refused load leaves the browser up
    with the banner and your place in the list rather than jumping the view
    away from something that did not happen. Same for an empty selection and
    for a row the model has no track for. Preview decks are excluded
    (`PlayerManager::isPreviewDeckGroup`) — previewing is a browsing action
    and must not throw you out of the browser. `[Tab],overview` is created by
    `LegacySkinParser` from the Overview `SingletonContainer`'s `trigger`
    attribute; skins that do not define it never create the control and
    `ControlObject::set()` on a missing key is a no-op, so this is inert
    outside Pioneered. Mirrors the existing `[Library],load_blocked` write a
    few lines above. Touches `src/widget/wtracktableview.cpp`.
    Skin side (same release, no patch needed): tapping the backdrop outside
    the settings panel now dismisses it. New `templates/settings_scrim.xml`
    (a transparent `#SettingsScrimArea` button pressing the same
    `[Skin],show_settings` toggle + `[Library],menu_disarm` pair as BACK),
    `settings.xml` (four of them fencing the panel — they also take over the
    centering `SettingsOverlay` did on its own), `style.qss` (clears every
    `WPushButton` face on `#SettingsScrimArea`, `[value="1"]` included: the
    scrims carry `show_settings` as their value, so they wear state 1 the
    entire time the panel is open). Fencing rather than one full-screen
    button behind the panel keeps the panel's own dead space inert — a tap
    that misses a button by a few pixels must not close the menu.
18. `rekordbox-playlist-order.patch` (added 2026-08-30, r27) — rekordbox
    playlists imported off a USB now keep their track order. `buildPlaylistTree`
    stored each entry keyed by rekordbox `entry_index` in a `QMap` (sorted by
    that key) but then read the entries back by looking up the synthetic indices
    `1..size` via `QMap::operator[]`, which is only correct when `entry_index` is
    exactly the contiguous set `{1..N}`. Real rekordbox exports write sparse and
    non-1-based `entry_index` values, so the lookup pulled tracks into the wrong
    slots — most visibly the trailing tracks of the device surfaced at the top
    of the playlist — and, because `QMap::operator[]` default-inserts on a
    missing key, injected phantom `track_id=0` rows for every index with no
    match. The loop now walks the inner `QMap` in its natural
    (`entry_index`-ascending) key order via `constBegin()`/`constEnd()` and hands
    out a fresh 1-based position, so it is correct for 0-based, 1-based, sparse
    or permuted `entry_index` and never materialises phantom rows. Only became
    visible once `rekordbox-import-fixes.patch` (8) fixed the PDB row count so
    playlists actually populate; before that they imported empty and the
    ordering weakness was hidden. Touches
    `src/library/rekordbox/rekordboxfeature.cpp`.
19. `rekordbox-unicode-paths.patch` (added 2026-09-14, r28) — the Mixxx half
    of "some tracks do not load". The reported file (`BASTI - La Mamá …mp3`)
    decodes cleanly (ffmpeg, CBR 320 kbps, ID3v2.3); what fails is *finding*
    it: the `á` makes the on-disk name depend on how the stick is mounted and
    on which Unicode normalisation form rekordbox wrote into `export.pdb`.
    The root-cause fix is in `pi/usb-mount.sh` (FAT sticks now mounted with
    `utf8=1`; without it the kernel names files in its default charset and
    the UTF-8 path from the PDB never matches, so `TrackDAO::addTracksAddFile`
    logs "File not found" and `loadSelectedTrackToGroup` silently drops the
    tap). This patch covers what Mixxx can do on its own: `insertTrack` in
    `rekordboxfeature.cpp` runs a non-ASCII path that does not exist as
    written through `resolveUnicodePath()`, which retries it in NFC and NFD
    (rekordbox on macOS writes decomposed names to FAT32 while the PDB string
    may be composed, or vice versa); ASCII paths never touch the disk. And
    `WTrackTableView::loadSelectedTrackToGroup` raises `[Library],load_missing`
    when the model has no loadable track for the row, which the skin shows as
    a "TRACK FILE NOT FOUND ON USB" banner (`LibraryControl` starts the shared
    banner timer and clears it, exactly like `load_blocked`). Touches
    `src/library/rekordbox/rekordboxfeature.cpp`,
    `src/widget/wtracktableview.cpp`, `src/library/librarycontrol.{h,cpp}`.
    Skin side: `skin.xml` banner + `style.qss`. Pi side: `pi/usb-mount.sh`,
    and `pi/update-pioneered.sh` now installs the `pi/` layer on every update
    so mount-script fixes actually reach the unit.
20. `wifi-settings.patch` (added 2026-09-14, r28) — WI-FI page in the
    settings menu, driven through NetworkManager's `nmcli`. New widget
    `src/widget/wwifipanel.{h,cpp}` (skin tag `<WifiPanel>`, registered in
    `LegacySkinParser::parseWifiPanel`, added to `CMakeLists.txt`) holds the
    dynamic part: status line with IP, up to N rows of networks (one per
    SSID, strongest first, CONNECTED / SAVED / OPEN / ENTERPRISE tags, signal
    bars), paging, and the password being typed. Every nmcli call is an
    async `QProcess` (a scan takes seconds; the GUI thread never waits),
    parsed from `-t --escape yes` output with a backslash-aware splitter,
    and retried through `sudo -n nmcli` when stderr says polkit refused.
    Connect is `nmcli -w 30 dev wifi connect <ssid> [password <pw>]` for
    saved, open and new networks alike; a failed attempt deletes the
    half-made profile so it cannot masquerade as SAVED, and a saved network
    whose stored password fails drops you into the password page with a
    hint. Tapping the connected network arms "TAP AGAIN TO FORGET" (5 s
    disarm, same pattern as POWER OFF). `LibraryControl` owns the controls
    (`wifi_open/back/rescan/prev/next/connect` presses, `wifi_page` and
    `wifi_entry` state) and forwards them to the bound panel via
    `Library::bindWifiPanel`, mirroring the search box; `menu_disarm` also
    closes the page so the cog always reopens on the main menu. The
    on-screen keyboard is generalised in `setupOnScreenKeyboard(prefix …)`:
    one control set per prefix (`search`, `wifi`), each with a one-shot
    `_shift` latch (drops on the shifted key's release), a `_symbols`
    latch, and punctuation keys named `_key_c<codepoint>` since the
    characters cannot name a ConfigKey. Both latches are TOGGLE-mode
    controls so a skin PushButton flips them per tap. `search_clear` joins
    `clear_search` so `keyboard.xml` can be one template. Touches
    `src/library/librarycontrol.{h,cpp}`, `src/library/library.{h,cpp}`,
    `src/skin/legacy/legacyskinparser.{h,cpp}`, `CMakeLists.txt`, plus the
    two new files. Skin side: `keyboard.xml` and `templates/kb_key.xml` are
    parametrised (`kb_prefix`, `kb_done_control`, `kb_done_label`; two faces
    per key bound to the shift latch; letter/symbol layers bound to the
    symbols latch), `search.xml` passes the search set (keyboard now 180f
    for 5 rows), `settings.xml` grows a WI-FI row (panel 354f) and wraps the
    menu in `SettingsMenuLayer` (hidden while `wifi_page`), new `wifi.xml`
    page, `style.qss` styles the page and the plain-Qt rows inside the
    panel by `QPushButton#WifiRow[rowstate=…]`.
21. `rekordbox-path-fallback.patch` (added 2026-09-14, r29) — the other half
    of "some tracks do not load", and the one that was actually biting.
    Patch 19 only covered a PDB/filesystem disagreement about Unicode
    *normalisation*; the field case was a FAT stick mounted without
    `utf8`/`iocharset=utf8`, where the kernel hands the accented character
    back in its default charset. No normalisation of the PDB name can equal
    that, so the load still did nothing. `pi/usb-mount.sh` fixes it at the
    mount (r28), but a stick mounted by anything else — an older
    `usb-mount.sh` that a partial update left in place, a desktop
    automounter, a hand-typed `mount` — still lands here. So after the exact
    path and both normalisations miss, `resolveUnicodePath()` lists the
    directory and matches on the name's *ASCII skeleton* (the name with every
    non-ASCII character removed): every mangling of an accent leaves the
    skeleton identical, so the file is found whatever the mount did to it,
    while a skeleton shared by two files — names differing only in accented
    characters — is refused rather than guessed. The listing is cached per
    directory and `thread_local`, so a whole stick in the wrong charset costs
    one `readdir` per folder instead of one per track and the concurrent
    per-device parse threads need no lock. A match logs a warning naming the
    mount fix, since needing it at all means the stick is still mounted
    wrongly. Touches `src/library/rekordbox/rekordboxfeature.cpp`.
22. `update-page.patch` (added 2026-09-14, r29) — SOFTWARE UPDATE in the
    settings menu: runs the on-Pi updater and shows its terminal output live,
    so the unit updates itself from the touchscreen. New widget
    `src/widget/wupdatepanel.{h,cpp}` (skin tag `<UpdatePanel>`, parsed by
    `LegacySkinParser::parseUpdatePanel`, added to `CMakeLists.txt`) runs
    `sudo -n /usr/local/bin/update-pioneered.sh --no-reboot`. The command is
    fixed in C++ rather than read from the skin deliberately: it runs as root
    and a skin is a folder of XML anyone can drop in. `-n` because nothing
    can answer a password prompt from there, so a missing sudoers rule fails
    at once with a readable message instead of hanging. Both streams are
    merged so the transcript reads as it would in a terminal; carriage
    returns become newlines so apt's progress lines stack rather than
    overwrite; ANSI escapes are stripped; `setMaximumBlockCount` caps the log
    so a long run cannot grow without bound on a 1 GB Pi; and `QScroller`
    makes it draggable, there being no wheel and no hitting that scrollbar
    with a finger. UPDATE is tap-again-to-confirm on the menu's existing 5 s
    disarm timer. While it runs, UPDATE and BACK are withdrawn; closing the
    page (or the whole menu) leaves the update running, and the destructor
    detaches from the process rather than killing it — a half-finished dpkg
    is much worse than a lost window. On success RESTART NOW appears, reusing
    the power-off ladder (logind, then passwordless sudo). Plumbing mirrors
    the Wi-Fi page: `LibraryControl` owns `[Library],update_*` and forwards
    to the panel bound via `Library::bindUpdatePanel`. One extra control,
    `menu_subpage`, is 1 while any sub-page is open, because a skin
    `Connection` drives a property from a single control and "menu hidden
    while Wi-Fi *or* update is open" would otherwise be two bindings fighting
    over `visible`. Touches `src/library/librarycontrol.{h,cpp}`,
    `src/library/library.{h,cpp}`, `src/skin/legacy/legacyskinparser.{h,cpp}`,
    `CMakeLists.txt`, plus the two new files. Skin side: new `update.xml`,
    `settings.xml` (SOFTWARE UPDATE row, panel 418f, menu now hides on
    `menu_subpage`), `style.qss`. Pi side: `pi/update-pioneered.sh` gains
    `--no-reboot` and installs itself to `/usr/local/bin/` — by temp file and
    rename, never a copy over itself, since bash reads a script as it runs
    and this script may *be* the one being replaced.

    Amended r30: `sudo -n` has two refusals of its own - `command not found`
    when the updater has never been installed at that path, and `a password
    is required` when the sudoers rule is missing - and both exit 1 with one
    line, exactly like an update that ran and failed. The page therefore
    ended at "UPDATE FAILED (exit 1)" for the only two problems a fresh unit
    actually hits; the readable message `-n` was chosen for only ever
    appeared when `sudo` itself could not be started, which never happens.
    `WUpdatePanel` now reads the two off the transcript as it scrolls past
    (`StartProblem`) and ends on "UPDATER NOT INSTALLED" or "UPDATE NOT
    PERMITTED", printing the command that fixes each. Neither can be fixed
    from the touchscreen: installing the updater is root work outside what
    the sudoers rule permits, which is why the page names a shell command
    rather than offering a button.
