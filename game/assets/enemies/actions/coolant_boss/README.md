# Coolant inspector Boss

Fifteen original, left-facing, articulated anime-mecha sprites generated with the built-in image generation tool. All frames are transparent 640×640 lossless WebP, registered at source anchor `(320, 600)`. Native standing body height is 400 pixels; the level-two integration uses a display body height of 265 pixels and scale `265 / 400`.

`manifest.json` has the existing enemy animation format: idle ×2, move ×3, attack_sweep ×2, attack_charge ×2, attack_wave ×2, hurt ×1, and death ×3. Each attack has a windup and contact pose. The low clean recovery pose is `attack_charge/01.webp`.

The ground-skimming cold disc emits from the actual horizontal drill tip in `attack_charge/02.webp`, source pixel `(13, 516)`. This is an offset of `(-203.3875, -55.65)` from the actor root when rendered at 265 pixels. Mirror the point around the same actor root when facing right; never offset the whole canvas as part of the mirror.

`hurt_regions.json` includes all twelve live poses. Vulnerable regions cover the torso, structural turbine and separately outlined legs and boots; drill and extending arms are excluded. Each pose has three contact samples and three misses (visible drill, transparent leg gap, above the body). All 72 point checks pass. Source pixel coordinates match the manifest and do not include display scaling.

Sources, exact prompts, extraction data, references, and the animated preview live outside the runtime asset folder in `qa/coolant-boss-art-source/`, which has `.gdignore` to prevent animation-preview import errors. Provenance is recorded in `prompts.json` and `charge-correction-prompts.json` there. No CLI/API image-generation fallback was used.

The original motion, attack and death atlases supplied genuine joint changes. The final low drill pose was a targeted built-in image edit to align the cold disc with its visible emitter. Extraction used connected alpha isolation, minimal alpha cleanup, uniform Lanczos downsampling and explicit root registration; it did not manufacture motion by whole-sprite jitter or flipping.

Static proof sheets and individual hurt-region overlays are under `qa/coolant-boss-art-*`. Regeneration scripts are `qa/coolant-boss-art-build.py` and `qa/coolant-boss-art-hurt-regions.py`.
