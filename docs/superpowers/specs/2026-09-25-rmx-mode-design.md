# RMX mode — design spec

**Date:** 2026-09-25
**Status:** Approved by user (interface plan), shipped in r40, revised in r41
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
  screen.

```
┌─ RMX ─────────────────────────────── DECK 1  124.0 BPM  ● ┐
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐              │
│ │ KICK │ │SNARE │ │ CLAP │ │ HAT  │ │BUILD │  pads        │
│ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘              │
│ ROLL                                                      │
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐           │
│ │1SHOT│ │ 1/1 │ │ 1/2 │ │▐1/4▌│ │ 1/8 │ │1/16 │  rates    │
│ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘           │
│                          LEVEL  [−]  80 %  [+]            │
└───────────────────────────────────────────────────────────┘
```

- **Header**: the deck the drums follow (DECK 1 / DECK 2, or FREE when no
  deck is playing), its BPM, and a light that flashes on every beat.
- **Pads and rates are about the same size** (r41). The pad row and the ROLL
  row share the height equally, and five buttons (four pads plus BUILD)
  against six rates keeps them close in width. In r40 the rates were a thin
  strip and hard to hit.
- **Pads**: tap = one hit, played at once. Hold = roll at the ROLL rate, on
  the beat grid. Each pad flashes on every hit. The colours are kick red,
  snare orange, clap green and hat blue.
- **ROLL**: radio buttons. 1 SHOT turns rolls off. The default is 1/4.
- **BUILD**: a two-bar snare roll that starts on the next beat. It goes
  1/2 → 1/4 → 1/8 → 1/16 and rises from 45 % to full level, so the drop
  lands on the beat after it. Tap again to stop it.
- **LEVEL**: steps of 10 %, 80 % by default.

**Multi-touch:** each Mixxx widget takes its own touch, so you can hold two
pads together, or hold a pad and change the rate while it rolls.

## Hardware

The DDJ-400 is untouched (r41). In r40, while RMX was open, the BEAT FX
buttons played the pads. The user dropped that: the screen is multi-touch,
so the pads don't need the hardware, and the Beat FX is more useful kept as
it is.

## Audio

- The drums join the master after the channel faders, the crossfader and
  the master effects, like an RMX in the mixer's send/return.
- They are **always in the headphones** (user request: quiet practice at
  home). They go in at the cue share of HEADPHONES MIX; the master share
  arrives with the main mix, so the headphone level of the drums does not
  change with the MIX knob.
- **They always go through the Beat FX** (r41, user request), whatever the
  CH SELECT switch says. The drums are an input channel of their own to
  Effect Unit 1, and it is always switched on, so LEVEL/DEPTH puts echo,
  delay or reverb on them. They are processed exactly once: with the Beat FX
  on MASTER they don't go through it a second time. The effect tail rings
  out for 10 s after the last hit.
- The drums are synthesised by code, so there are no sample files.

## Implementation

See `mixxx-patch/VERSION.md` entry 37 and the `rmx.patch` header. In short:
`EngineRmx` is owned by `EngineMixer` and runs after the decks each
callback. Timing is exact to the sample, taken from the master deck's
`beat_distance` and `bpm`. The drums then go through the Beat FX on their
own `[PioneeredRmx]` input before they are mixed into the outputs.

## Out of scope (v1)

Scene FX, Isolate FX, Release FX, the sequencer, and switching drum kits.
