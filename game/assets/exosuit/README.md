# Original piloted firepower exosuit

Twenty unique generated mechanical poses, with separate registered Silverwing and
Feiren driving overlays. The design is an original ivory, gunmetal and amber biped,
with a near-arm rotary cannon and separate shoulder recoil cannon.

## Runtime contract

- Read `manifest.json`. `animations[action].frames[index]` selects a key in `frames`.
- Draw the selected `frames[key].pilots[identity]` first when a pilot is aboard,
  followed by `frames[key].texture`. Paths are relative to this directory.
- Both layers are 640×640 transparent lossless WebP, already registered. Do not
  independently resize, reposition or re-mask the pilot overlay.
- Root is (320,592). Nominal standing silhouette height is 420 source pixels.
  At scale 225/420 the canvas is 342.857 world pixels and body is about 225 pixels.
- Mirror BOTH layers about x=320. Native muzzle and other points mirror using
  `x_left = 640 - x_right`. Coordinates are image-space pixels, not root offsets.
- The two muzzle keys are `rotary` (light gun) and `heavy` (shoulder cannon).
- Suggested stable physics capsule is radius 50, total height 150 world pixels,
  centered at root+(0,-75). Drawn barrels must not expand terrain collision.
- Per-pose native hurt-body polygons are visual guides. Use the stable gameplay
  collision shape for movement and safe exit placement.

## Animation and honesty notes

There are 2 parked, 2 mount, 2 idle, 4 walk, 2 rotary-fire, 2 heavy-fire, 2 jump/boost,
1 hurt and 3 progressively collapsed destruction drawings. They are distinct
generated articulated poses, not translations of one standing picture.

`exit` deliberately reuses `mount_00` and `parked_01`. It is an opening sequence,
not a separately drawn human climbing-out animation. Draw the on-foot hero after
the exit completes. The parked chassis and destroyed wreck have no pilot.

The pilot is actually seated with hands on two control sticks. Silverwing has blue
eyes and blue armor accents; Feiren has orange eyes and red/orange armor accents.
At the proposed gameplay size the pilot face is compact. No standing hero image
or sword is embedded in the cockpit.

Each source keyframe was normalized independently onto the same virtual foot plane.
Generated mechanical details vary slightly between poses; walk poses have visible
leg articulation, and weapon poses have distinct gun/torso positions. Jump uses
real tucked and extended legs and relies on game physics to move the root upward.

The complete runtime set is 60 WebP files, 4,203,800 bytes (4.009 MiB), plus metadata.
This exceeds the initial 3 MB aim to preserve lossless detail and clear pilot faces.
Full-resolution source art is excluded from Godot import under the QA directory.

## Source and QA

`qa/exosuit-art-source/` contains source sheets, exact image-generation prompts,
the deterministic packaging script, contact sheet, identity/mirror comparison,
muzzle-origin marks, both animation GIFs and machine-readable QA results.
All drawn art used the built-in `image_gen` tool. Packaging only sliced complete
keyframes, uniformly resampled them, registered anchors, masked pilot layers and
encoded lossless WebP. No new poses were manufactured by image jitter.
