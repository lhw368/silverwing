# Furnace enemies, v0.8

Two original industrial enemy classes, generated with the built-in `image_gen`
tool on 2026-10-06. Clean cel-style raster artwork with burnt-orange armor and
gunmetal mechanisms. Existing enemy art, drone art, and game scripts are untouched.

- `lancer/`: slender lance-equipped dash/thrust biped.
- `minelayer/`: broad short-legged mine-deployment robot with a disk hopper.

Each class contains **12 genuinely distinct drawn animation cels**: two each for
`idle`, `move`, `windup`, `attack`, `hurt`, and `death`. Idle and move loop; the
other groups are one-shots. The death sequence ends in a fully collapsed pose.
These are generated joint/limb poses, not rotations or wobble applied to a single
sprite. All frame textures are lossless WebP with genuine alpha transparency.

## Registration and rendering

Both classes use a `576 × 384` canvas and a fixed foot/root anchor at `[288, 350]`.
The anchor is aligned to the physical pelvis horizontally and planted contact
vertically, independent of the weapon/hand bounding box. Every pose uses one
uniform scale per class. Small 0–2 native-pixel antialias fringe below the root is
expected; at game scale this is less than one pixel.

| Class | Native upright body height | Suggested in-game body height | Render scale |
| --- | ---: | ---: | ---: |
| lancer | 297 | 130 | 130 / 297 |
| minelayer | 276 | 130 | 130 / 276 |

The artwork faces **right**. Mirror with the enemy's facing directly; do not copy
the negative-facing convention used for the older left-facing enemy artwork.
Use the full frame-size and root metadata rather than fitting the alpha bounds
per frame. Fitting each pose independently will make the actor grow or shrink.

`windup` is a separate animation group. Attack frame 0 is the thrust/deployment
contact and frame 1 is follow-through/recovery. Keep gameplay timing authoritative.
The provided fps values are defaults, not new combat timings.

Each frame in `manifest.json` carries its size, root, alpha bounds, source crop,
uniform scale, source registration, SHA-256, and body polygons. The same body
polygons are grouped by action in `hurt_regions.json`. They describe the main
chassis and separate legs; lances, ground mines and extended tools are excluded.
To transform a polygon, subtract the anchor, multiply by the render scale, mirror
x for a left-facing actor, and add the world foot position.

`minelayer/mine.webp` is an optional isolated disk extracted from the generated
attack-follow-through cel. `mine.json` supplies its root, source crop and a
suggested 38-pixel display width. It can serve as the persistent world-mine art.
The disk painted into the attack cel itself is visual only.

## Provenance and QA

`qa/v08-enemy-art/` contains:

- Exact generation prompts and both unmodified generated source sheets as
  lossless WebP archives.
- Deterministic extraction script, registered transparent sheets, contact sheets,
  body-polygon overlays and per-state animated GIF previews.
- A 130-pixel body-scale preview and `validation.json`.

Extraction only separates source alpha components, removes nearly invisible
generation haze (alpha ≤ 4), applies one uniform scale per actor, and registers
the original pixels. No character poses are synthesized or recolored by code.
There are no licensed-character assets or external asset-pack dependencies.
