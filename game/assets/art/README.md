# Starport MVP environment and enemy artwork

Generated with the built-in imagegen tool on 2026-10-04 using the approved Silverwing starport concept as a visual design reference. The background is a newly generated clean plate, not the concept image reused as a game screen. Exact prompts and generation output locations are in `generation_prompts.json`.

## Runtime assets

| Relative to assets/ | Pixels | Use |
| --- | --- | --- |
| environment/starport_background.png | 1672 × 941, RGB | Wide parallax background; no actors, HUD, text or foreground gameplay floor |
| environment/platform_strip.png | 2172 × 284, RGBA | Horizontal platform deck + structural side; draw top edge at collision floor height |
| enemies/melee.png | 503 × 462, RGBA | Agile claw robot, facing left |
| enemies/shield.png | 522 × 496, RGBA | Tower shield robot, facing left |
| enemies/drone.png | 395 × 257, RGBA | Floating single-eye drone, approximately front/three-quarter view |
| enemies/boss.png | 757 × 492, RGBA | Heavy cannon boss, facing left |
| enemies/repair_npc.png | 267 × 306, RGBA | Friendly white round repair robot, facing three-quarter right |

Humanoid and repair sprites use bottom-center anchors; drone uses a center anchor. Enemy sprites are single-frame cutouts for MVP transform-driven animation, not multi-frame animation sheets. Horizontal flipping can change facing. Preserve aspect ratios.

The generated platform is visually joinable but not a pixel-perfect seamless texture. Join/repeat under small mechanical ribs or use the long strip as a single platform piece if needed. No colliders are baked into the art. The clean background is a single plate; parallax is code-driven.

## Preserved sources and extraction

- `enemies_atlas_original.png`: unmodified 1536 × 1024 generated transparent sprite atlas.
- `platform_strip_original.png`: unmodified 2172 × 724 generated transparent platform plate.
- `enemies_atlas_map.json`: exact crop rectangles, output dimensions and anchor guidance.
- `atlas_alpha_preview.jpg`: visual inspection composite on a solid blue background; not a runtime sprite.
- `generation_prompts.json`: complete prompt set and original generated file locations.

Sprites were extracted with deterministic rectangle cropping only. Original generated alpha and RGB pixels were preserved. Bounds were identified from alpha values above 4, with a small surrounding margin. Platform extraction was a deterministic crop `(0, 261, 2172, 545)`. The original generated assets were left unchanged. Alpha was verified as real transparency rather than a baked checkerboard or solid background. No generated imagery was synthesized or repainted by code.

## Suggested initial in-game proportions

These are presentation suggestions, not collision dimensions: melee display height around 145 px, shield around 160 px, drone around 70 px, boss around 225 px, repair NPC around 86 px. Adjust with the player's runtime height to preserve combat readability.
