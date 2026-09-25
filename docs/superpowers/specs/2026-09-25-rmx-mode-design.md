# RMX mode — design spec

**Date:** 2026-09-25
**Status:** Approved by user (interface plan), shipped in r40
**Delivery:** Skin (`rmx.xml`, two templates, `effects.xml`, `overview.xml`,
`style.qss`) plus `mixxx-patch/rmx.patch` (37th in the CI series).

## Goal

A few of the Pioneer RMX-1000's X-PAD tricks: drum pads that add a kick,
snare, clap or hat on top of the mix, with rolls locked to the beat. Played
from the touchscreen and from the DDJ-400's BEAT FX buttons. It does not
copy the whole RMX-1000.

## Interface

- **RMX button**: a full-width button under the Color FX grid, 44 px tall,
  in the accent colour when lit. Tap to open, tap again to close.
- **Panel**: takes the place of the two scrolling waveforms only. The BeatFX
  column (with the RMX button) and the deck strip with its overviews stay on
  screen. While it is open, a note under the button reads
  "BEAT FX KEYS PLAY PADS".

```
┌─ RMX ───────────────────────────── DECK 1  124.0 BPM  ● ┐
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐             │
│ │  KICK  │ │ SNARE  │ │  CLAP  │ │  HAT   │  pads       │
│ └────────┘ └────────┘ └────────┘ └────────┘             │
│   ◀ BEAT     BEAT ▶    FX SELECT   ON/OFF   hardware    │
│ ROLL [1 SHOT][1/1][1/2][▐1/4▌][1/8][1/16]               │
│ [      BUILD      ]  LEVEL  [−]  80 %  [+]              │
└─────────────────────────────────────────────────────────┘
```

- **Header**: the deck the drums follow (DECK 1 / DECK 2, or FREE when no
  deck is playing), its BPM, and a light that flashes on every beat.
- **Pads**: tap = one hit, played at once. Hold = roll at the ROLL rate, on
  the beat grid. Each pad flashes on every hit. The colours are kick red,
  snare orange, clap green and hat blue.
- **ROLL**: radio buttons. 1 SHOT turns rolls off. The default is 1/4.
- **BUILD**: a two-bar snare roll that starts on the next beat. It goes
  1/2 → 1/4 → 1/8 → 1/16 and rises from 45 % to full level, so the drop
  lands on the beat after it. Tap again to stop it. The button stays lit
  while the roll is running.
- **LEVEL**: steps of 10 %, 80 % by default.

The touchscreen only takes one touch at a time, so on screen you pick the
rate before you play. On the hardware you can hold a pad and turn the knob
at the same time, which is how you sweep a roll into a build.

## Hardware (DDJ-400, only while RMX is open)

| Control | RMX |
|---|---|
| BEAT ◀ | KICK |
| BEAT ▶ | SNARE |
| FX SELECT (and SHIFT + FX SELECT) | CLAP |
| ON/OFF | HAT |
| SHIFT + ON/OFF | BUILD start/stop |
| LEVEL/DEPTH | roll rate 1/1 (left) … 1/16 (right) |
| SHIFT + LEVEL/DEPTH | drum level |

When RMX is closed, the buttons control the Beat FX exactly as before, and
the Beat FX settings are untouched. Closing RMX releases any held pad and
stops a BUILD.

## Audio

- The drums go on the master after the channel faders and crossfader, like
  an RMX in the mixer's send/return.
- They are **always in the headphones** (user request: quiet practice at
  home). They go in at the cue share of HEADPHONES MIX; the master share
  arrives with the main mix, so the headphone level of the drums does not
  change with the MIX knob.
- The drums are synthesised by code, so there are no sample files.

## Implementation

See `mixxx-patch/VERSION.md` entry 37 and the `rmx.patch` header. In short:
`EngineRmx` is owned by `EngineMixer` and runs after the decks each
callback. Timing is exact to the sample, taken from the master deck's
`beat_distance` and `bpm`. The hardware routing is done in
`MidiController`, not in the mapping script, because a stale user copy of
the mapping shadows the shipped script.

## Out of scope (v1)

Scene FX, Isolate FX, Release FX, the sequencer, and switching drum kits.
