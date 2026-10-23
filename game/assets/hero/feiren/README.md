# Feiren / 绯刃 combat art

Thirty distinct animation cels for the v0.7 rescue and playable-character update. Built-in imagegen created new character artwork from the original Feiren identity, with Silverwing used only for the established smooth cel-shaded game style. This is not a recolor. Original generated sheets, exact prompts, extraction script, and previews are in `qa/feiren-art-source/`, protected from Godot import by `.gdignore`.

## Runtime registration

- Transparent, lossless RGBA WebP, 512 × 512 pixels per frame.
- Ground/body root: **(256, 474)** in every frame; no per-frame runtime offsets.
- For a centered Godot Sprite2D: offset **(0, -218)** before scaling.
- Keep the approved **264px draw canvas**, corresponding to about 154px standing visible height in world space.
- Flip about x=256/root, never about the visible artwork bounds. Weapon width must not change the root.
- Uniform 0.594 source downsample preserves head and armor proportions; crouched poses are intentionally shorter. Standing artwork is about 298px tall.
- The registered blink was separately generated at 1254² and downsampled to the same body size and boot placement.

## Animation use

`manifest.json` is authoritative and lists actual `.webp` paths in order, playback settings, source bounds/anchors, visible bounds, hashes and file sizes.

- idle: 00 is alert stance; 01 is a brief blink. Hold 00 for 2.68s, show 01 for 0.12s. Do not hold the blink for half the idle cycle.
- run: 6 gait cels at about 10fps; 02/05 are flight phases, with intentional toe clearance of about 9px. Registration already includes this motion.
- jump: 00 takeoff, 01 rise, 02 apex, 03 fall, 04 landing. The engine moves the root through the jump trajectory.
- attack1: startup and horizontal contact; attack2: rising contact; attack3: low finishing contact.
- heavy: overhead windup and downward contact.
- dodge: coil and low slide.
- skill: startup, forward travel, finishing contact. This is Feiren's short fiery sword dash; the small flame belongs to the blade. Add large contact/gameplay effects in code.
- hurt: backward recoil.
- death: kneeling collapse, then side-lying final pose.
- rescue: friendly right-facing wave.
- cockpit: 2 seated control poses. Place and scale explicitly within the vehicle interior.

## Provenance and QA

- 31 generated poses were reviewed; 30 are used. The initial wider second idle stance remains only in its original source sheet and was replaced with a registered blink to avoid idle foot movement.
- The five main sheets are 1536 × 1024, six poses each. Standing/run native silhouettes are roughly 450–500px tall. Compressed crouch/death poses have shorter silhouettes at the same head/body scale; no small art was enlarged and claimed high resolution.
- Extraction performs connected-component isolation, preservation of nearby generated alpha, uniform Lanczos resampling, transparent padding, and lossless WebP encoding. It does not interpolate poses, duplicate/rotate limbs, or mirror one drawing to invent another.
- Every output is read back and checked for exact pre-encode RGBA equality. All frame paths exist; every frame is RGBA 512²; all frames have clear canvas borders.
- See `qa/feiren-art-source/qa-report.json`, the 30-pose contact sheet, the light-background idle/run anchor review, and the animation preview.
