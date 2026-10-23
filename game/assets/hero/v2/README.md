# Silverwing visual-quality revision

Runtime contract: **512×512 RGBA**, right-facing, fixed ground origin **(256,474)**. Keep the gameplay draw rectangle at **264×264 world pixels** for the same-size comparison. This produces an approximately154px visible standing character. For a centered Sprite2D, use local offset `(0,-218)` before scaling.

Use **LINEAR without mipmap blending** for the hero at the current264px world draw size. Actual Godot captures showed that mipmap blending softened eyes and hair; a subsequent LINEAR capture retained smoother contours with crisper detail. Do not use nearest filtering or pixel snapping for this cel-shaded artwork. No global blur is part of this asset revision.

## What genuinely changed

- **Idle:** a new1351×1164 standalone drawing with1148px native character height, downsampled at0.26 into this512px canvas. This is newly generated detailed art, not the old sprite enlarged.
- **Run:** six new key poses drawn at462–484px native character height, downsampled at0.62. Suggested9fps for a0.667s loop. These replace the older189–197px-high pet drawings.
- **Other combat:** existing source sheets had substantially more detail than the first320px extraction. These are re-extracted at1.024× source size instead of0.64×, retaining native detail. The tiny2.4% normalization enlargement is not claimed as new detail.
- **Jump:** source body heights338–461px are downsampled at0.672 instead of0.42, preserving more native detail.

The original320px runtime frames have not changed; QA verifies all26 original file hashes. The new set has **24 unique frames**: idle1, run6, jump6, attack1×2, attack2×1, attack3×1, heavy2, dodge2, skill1, hurt1, death1. This remains key-pose animation, not a densely hand-drawn production animation cycle.

At the same153–154px on-screen character size, the display still limits visible facial/armor detail. Better source art and sampling improve edges and consistency without claiming that512px file dimensions alone create additional visible detail.

## QA and sources

- `manifest.json`: authoritative state mapping and FPS recommendations
- `qa-report.json`: dimensions, alpha, border/clipping checks, source pixel audit, run baseline bounds, unchanged-v1 hashes
- `qa/contact-sheet.jpg`: every final frame
- `qa/same-size-sprite-comparison.png`: offline sprite-only diagnostic at identical264px draw canvas; it is not a gameplay screenshot
- `qa/run-cycle.apng`: six-frame motion diagnostic, fixed origin and baseline guide
- `source/silverwing-idle-native-v2.png`: new high-native-detail idle source
- `source/silverwing-run-sheet-v2.png`: new native run sheet
- `../prompts/idle-v2.txt`, `../prompts/run-sheet-v2.txt`: exact generation prompts
- Remaining sources: `../source/silverwing-combat-sheet.png`, `../source/silverwing-jump-sheet.png`
- `extract_assets_v2.py`: deterministic extraction, crop, normalization and QA-contact-sheet generation

The built-in image-generation tool was used. Source and diagnostic folders contain `.gdignore` so Godot does not import/export these large non-runtime images. Only the state folders should be used as runtime animation textures.

## Final in-game comparison

Actual Godot screenshots are in the project `qa/` directory. `hero-quality-comparison.png` compares `hero-before.png` with the final `hero-after-linear.png`, using identical178×172 pixel crops from1180×663 screenshots and a clearly labeled3× nearest-neighbor zoom. No pixels were retouched. `hero-quality-comparison.json` stores source hashes and crop coordinates. The mipmap test was rejected because it visibly softened the eyes/hair. Final hero rendering uses LINEAR without mipmap blending.
