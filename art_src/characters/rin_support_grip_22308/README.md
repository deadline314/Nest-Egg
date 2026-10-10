# Rin native support-hand source 22308

Status: **registered native support-hand partial delivery**. This packet preserves the raw Qwen edit and the SAM extraction used to produce the 226×142 support-hand crop. The Qwen render is RGBA but has no transparent pixels: alpha ranges from 252 to 255. The delivered hand transparency therefore comes from the separately recorded binary SAM 3.1 owner mask, not from the Qwen render's alpha channel.

The Rin recipe registers this source rebuild; the side spec exports the same native pixels into hand_left_grip with its own texture density. Runtime validates that density and restores the original hand when leaving the grip state. This registration changes the rear support hand only, and does not approve the complete character.

## Provenance

- Raw edit: `source/rin_ne222_support_context_22308_0.png`, 768×768 RGBA, SHA-256 `993fed5e839300642bb0e0ce9ba841de8d02c6ea7529ef750ecfce1d38d30c3a`.
- Qwen graph/job/history key and prompt are preserved under `source/`: graph node graph, job metadata (`key=2b1fc4bab5bb745f54b386d2419187eefe3f90e8`), `candidate.json`, and generation log. The request used seed 22308, 25 steps, CFG 1, Euler/simple, resolution 768, Qwen Image 2.1 UC INT8, Qwen 3 VL 8B INT8, Qwen Image 2.1 VAE BF16, cache device `off`.
- The edit input was an actual Forward+ rifle-hand crop, `source/actual-rifle-back_human-crop-native.png`, 320×240, SHA-256 `62d42bfa01e7a96f3134a91521b60ea444b2ec32efac37fe041ac77b3ae67ca0`; crop rectangle in the 1536×1216 native capture was `[1011,433,1331,673]` (right/bottom exclusive). It was enlarged 2× with nearest-neighbor and placed at `[64,144]` on the 768×768 transparent reference canvas. That exact input reference is also preserved as `source/actual-support-context-nearest2-reference.png` with SHA-256 `1aea812967ced6ab731ab06aeba3f6ffbba70940d0b6199079438d9802e13da4`.
- SAM 3.1 ownership is preserved in `sam/`: binary mask, raw mask output, positive/negative point specification, graph and log. Positive points: `(311,409)`, `(376,473)`, `(445,455)`, `(471,410)`; negative points: `(370,315)`, `(207,418)`, `(516,477)`, `(312,522)`. Checkpoint `sam3.1_multiplex_fp16.safetensors`, threshold 0.3, 2 refine iterations, one mask. The mask hash is `70a724378cb2f452be7465f845af5ce26db83cc6295ebd88a25316900a888baa`.
- The binary owner is one 8-connected component with 23,399 opaque pixels and bbox `[267,358,493,500]`. The crop preserves the raw Qwen RGB bytes within this owner and replaces alpha with the SAM owner. There is no resampling.

## Registration and output

The existing Rin `hand_back` slot has grip offset `[1.67408,-0.01506]` in skeleton units; the referenced original hand is 90×70, pivot `[15.89,35.51]`, scale `0.04205`. At body scale 1.15 and camera zoom 23.78, the recorded rifle foregrip implies wrist source point `(293.0822,383.9259)` in the Qwen canvas. The native crop's foregrip is `(160.3221,119.5511)` and the derived wrist is `(114.5411,119.9629)`. The foregrip is an attachment landmark, not the palm center.

The candidate remains at its source resolution and uses size 226×142, wrist pivot `[26.0822,25.9259]`, and texture scale `0.018283541156251144`. The underlying bone, rest pose, grip offset, weapon, and world-scale registration are unchanged. The normal map is produced by the existing `tools/comfyui/cut_layers.py:make_normal_map` helper from the cropped RGB and SAM alpha; its output is 226×142 and carries the same alpha.

`rebuild.py` verifies pinned input hashes and metadata before writing, derives the crop from the mask bbox, and emits both candidate textures. It includes one-pixel extra/missing owner, source hash, bbox, scale, and pivot negative controls. Two independent CPU replays produced byte-identical diffuse and normal outputs, matching the packaged candidate files:

- `hand_back.png`: `d4da7778be1c6df46797795d2aff09799bb928fa645df278afe16825a2ee4f89`
- `hand_back_n.png`: `22e3eeeb6699cdfd7b0141b2418661b85d40e2ebe9ffb78afd33e96d5ef8e6a7`

Replay logs and both build manifests are preserved in the public NE-222-native-support-hand attachment. To rebuild from this packet:

```powershell
D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_support_grip_22308/rebuild.py --out art_src/characters/rin_support_grip_22308/overrides
```

## Native production review and limits

The public portable fixture uses the actual CharacterRig.setup/animate grip API and ResourceLoader/LitTextures. Both variants clone the same archived legacy skin; only the support-grip definition changes before setup. There are no per-frame texture, scale, pivot, or attachment edits. The final Forward+ replay records 108 untouched 1536×1216 PNGs and 1,274 fixture checks, zero errors. All seven current Player weapon visual IDs have horizontal/up/down aims and both facings; normal-disabled/white-background and state-restoration controls are also included. The native change detector (at least 100 changed pixels per pair) is a smoke control, not an anatomy or seam acceptance threshold.

The public CPU fixture passes 458 checks. CharactersSuite passes 559 checks; the same test against the previous rig produces 16 real failures without script errors. The fixed aa51e05b affected-range run uses eight headless processes, 60 registered groups, 18,979 checks, zero new/known failures. A deterministic full export control passes 68 checks and preserves every other source part and existing grip offset. Two source rebuilds each pass 45 checks and produce identical native outputs.

The rear support hand is a partial delivery. The weapon occludes its opposed thumb at the current draw order. The front mechanical hand, complete silhouette/material lighting, crouch and all-motion joint acceptance remain separate requirements. Neither source-owner alpha nor a fixture check certifies the whole character. Evidence, archived original textures, native images, failures and replay commands are in ../../../pm/Nest-Egg/attachments/NE-222-native-support-hand/README.md.

Current ranged Player WeaponData IDs and visual IDs are: rifle → rifle, spread → shotgun, smg → smg, railgun → railgun, launcher → launcher, laser → laser, pistol → pistol, mech_cannon → rifle. RigInput.two_handed is a runtime input default rather than a WeaponData field. This fixture coverage does not certify every weapon's grip artwork or handling.
