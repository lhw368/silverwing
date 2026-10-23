# Furnace Boss · broken-armor second form

Original continuation of the existing furnace boss, generated with its actual idle and sweep sprites as references. The orange slit visor, twin rear antennae, circular chest furnace, heavy short-legged proportions, silver/gunmetal shell, and left forearm cannon remain recognizable. Broken armor exposes red-hot ribs and joints. The other hand carries a distinct industrial laser axe.

Eight real action drawings are supplied as transparent, lossless WebP frames:

- `idle/01.webp`
- `move/01.webp`
- `axe_windup/01.webp`
- `axe_attack/01.webp`
- `recover/01.webp`
- `hurt/01.webp`
- `phase_transition/01.webp`
- `death/01.webp`

These are eight separately drawn poses, one per state. They are not duplicate frames, translated copies, palette swaps, or a fabricated multi-frame walk cycle. The optional transition pose includes detached shoulder armor. The death is a separately generated kneeling collapse; the original crowded atlas's death quadrant is not used.

## Registration and rendering

Every runtime frame is 768×768 RGBA, faces left, and registers to `(384,710)`. Mechanical boot soles determine the vertical ground baseline; weapons and emissive edges may extend slightly below it. Death uses the visible mechanical boot baseline, so the fallen axe extends below the boot line due to the illustration's slight perspective. The agreed standing body height is 438 native pixels, matching the phase-one family. Render scale `265.0/438.0` keeps its established world height.

Use the `animation_groups` paths in `manifest.json`. It also contains `frame_size`, `root`, and `native_body_height` aliases for the existing game's metadata conventions. Each frame records its source crop, source registration root, exact resize factors, output alpha bounds, SHA-256, and weapon anchors. Source-facing mirroring must transform the native geometry around x=384.

The attack frame's laser blade center and cutting-edge points are in `frames[].weapon`. The center sits about 200 world units forward at the agreed world scale. Damage geometry should follow the axe's visible sweep; the forward cannon does not define axe reach.

## Hurt regions

`hurt_regions.json` groups native polygons by animation action, using the existing `frames[action][frame_index].polygons` pattern. Head/torso, legs, and feet are separate from weapons. Authored body regions are clipped to visible alpha and subtract foreground axe blade/shaft areas, followed by a one-pixel inward guard and deterministic outline simplification. No cannon, axe, shaft, detached plate, particle or empty leg gap is intentionally included. Dead-state geometry is provided only for QA; dead bosses should not receive damage.

`qa/v08-boss-art/validate_boss.py` checks all paths and frame hashes, genuine distinct frames, alpha, canvas/anchor consistency, hit/miss witnesses, and polygon visibility. The final validation has greater than 99.9% visible-alpha occupancy for all body polygons. Inspect the individual `*-hurt.jpg` overlays: green polygons are damageable body, red circles are explicit excluded weapon/transparent-gap samples.

## Provenance and reproducibility

Built-in `image_gen` generated the actual pixels. The prompt set is in `generation-prompts.txt`. `sources/` preserves three generated images as exact lossless WebP, totaling 3.49 MB. Runtime images total 2.23 MB. No source is upscaled: standing poses use 0.97–0.98×, and the larger death source uses 0.44×. Every source and sprite remains local to this project.

Run from the project root:

    python qa/v08-boss-art/extract_boss.py
    python qa/v08-boss-art/validate_boss.py

The extractor performs only deterministic subject isolation, alpha cleanup, crop/downscale, canvas registration, and collision/QA metadata construction. It never paints or synthesizes body parts. The transition's foreground axe silhouette is isolated with a recorded polygon because it touched the unused death pose in its generated atlas. The clean standalone death source avoids any missing-pixel reconstruction.

No production Godot scripts were changed by this artwork task.
