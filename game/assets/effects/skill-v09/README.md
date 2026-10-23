# v0.9 skill effects

Runtime helper: `scripts/skill_presentation.gd` (RefCounted). It reads gameplay state and draws; it never changes damage, collision, movement, cooldown, attack timing, hitstop, global RNG, or projectile life.

## Integration contract

- Construct one helper on the final game script.
- `on_skill(game, serial)` immediately BEFORE the `super.player_strike` call on the first active tick of a character skill. This registers the serial before immediate Feiren melee feedback. Do not call for exosuit commands.
- `on_hit(game, serial, contact, blocked)` from accepted `enemy_hit_feedback`. Use that function's existing authoritative contact/fallback, not a visual guess. Unrelated serials are ignored.
- `tick(dt, game)` AFTER authoritative simulation. The helper internally freezes when paused, clears at non-play modes, and respects `effects_enabled`.
- `draw_back(game)` before drawing the hero; `draw(game)` after ordinary world effects. They use the game's existing world draw transform.
- Suppress the original friendly projectile cyan arcs when `handles_projectile(shot)` returns true; leave hostile shots and vehicle shots alone. The helper retains a thin visible rail core when F8 disables decoration.
- `reset()` on `clear_combat()` / scene changes.

Silverwing keeps the same 0.24-second startup, 640px/s projectile, 0.85-second life, 36px collision radius, 24 damage, and per-enemy serial deduplication. VFX are a travelling laser pulse, never a new hitscan ray. Charging coils, converging filaments, white beam core, envelope, end-of-life contraction and confirmed contact starbursts follow that original timing. Ground/world collision is read only. Wall flashes come from the last actual projectile swept segment, including a blocked muzzle; enemy flashes only come from `on_hit`.

Feiren keeps her 0.10–0.40-second movement phase, existing strike interval and 42-damage melee shape. The new authored fire animation follows the real character root/weapon, with shorter world-position trails and rising embers. Textures are cropped around actual third-stage collision rectangles in both facings so fire does not paint over platforms or through cover. The main plume draws behind the hero; short contact bursts draw in front. No full-screen tint, bloom overlay or obscuring screen flash is used.

## Authored fire asset

`feiren-flame-sheet.webp`: 1536×1024 RGBA, six distinct 512×512 cels in a 3×2 sheet. Each cel is a rightward flame tip with leftward trailing tongues. The helper samples a 478×288 UV window at cell offset (26,125), with hot-tip registration near (495,294). Playback is 24fps, not a repeated/recolored single frame. Runtime maximum main plume is 193×101 world pixels; contact plumes max out near 143×93.

Built-in imagegen generated the sheet using the existing Feiren skill frame as a style reference. A second imagegen edit removed the background into genuine alpha. The original generated PNG and the exact two prompts are in `qa/v09-skill-source/` (excluded from Godot imports with `.gdignore`). Lossless WebP encoding reduces the runtime sheet to about 556KiB; decoded alpha and every RGB channel at nonzero alpha were checked exactly equal to the PNG. Fully transparent hidden RGB may be optimized by WebP. This is effect-only art, not a concept illustration reused as a sprite.

The laser uses code-native antialiased lines, rings and polygons appropriate to a geometric energy effect. No emoji, recolored character image or invented hitbox is used.

## Resource limits and checks

- 56 motes, 16 fading flame trails, 20 localized flashes, 8 tracked attack serials.
- Independent deterministic RNG prevents cosmetic particles from changing combat/loot random sequences.
- `qa/v09-skill-regression.gd` runs against the actual game and collision helpers. `qa/v09-skill-results.json` reports the final checks.
- `qa/v09-skill-source/flame-alpha-review.png` is an offline alpha-composited sprite review, not a gameplay screenshot.
- Headless Godot 4.6.3 checks compile/import, damage, one-hit behavior, both-facing cover, blocked muzzle, crop geometry, pause, F8, death/reset, particle caps and global RNG independence. Actual game screenshot QA belongs to the integrated game run, because this worker's shell has only the headless/dummy display.
