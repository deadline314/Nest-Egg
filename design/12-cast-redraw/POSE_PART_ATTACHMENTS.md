# Pose-part attachment interface

`CharacterRig` accepts an optional `pose_parts` object in a character definition. It lets a caller explicitly select a prevalidated set of replacement sprites while retaining the canonical skeleton and each part's existing bone parent.

```json
"pose_parts": {
  "kneel": {
    "texture_scale": 0.030421,
    "parts": [
      {
        "slot": "armor_pelvis",
        "texture": "kneel_pelvis",
        "bone": "hip",
        "offset": [0, 0],
        "rotation": 0
      },
      {
        "slot": "pelvis_dmg",
        "texture": "kneel_pelvis_dmg",
        "bone": "hip"
      }
    ]
  }
}
```

Each set must have a nonempty `parts` array. `slot` is the unique logical `parts[].name`, not a texture alias. Each entry references a texture definition in the same character's `textures` map; that definition supplies the native `file`, `size`, and `pivot`, plus the matching normal map and optional glow path. `bone` must match the base part's existing bone. `offset` and `rotation` are optional and default to that base node's local transform. `texture_scale` is an optional positive finite world-units-per-source-pixel value shared by the set; if omitted, the character's `texture_scale` is used. For example, source density `32.872` pixels per world unit corresponds to `1 / 32.872 ≈ 0.030421` world units per source pixel. Keep the authored PNG at native resolution.

`set_pose_parts(&"kneel")` selects the set; `set_pose_parts(&"")` clears it. An unknown key returns `false` and preserves the current selection. Setup validates every entry in a set before constructing its alternatives. A malformed or incomplete set is rejected with a path-specific warning, leaving the base rig usable. Selection switches cached nodes and does not allocate per-frame dictionaries; selecting the already active key returns immediately. Alternatives reuse the base slot's bone, z-order, lighting material, tint, fill, dissolve, and facing flip. If a pose replaces an armor part or one of its same-bone underlayers, the same set must replace its counterpart so armor loss cannot reveal art from another pose. A selected alternate is hidden whenever its base logical slot is currently ineligible; clearing selection restores whichever base parts are currently eligible.

Eye slots managed by `eye_states` are currently rejected because the attachment API does not coordinate replacement textures with the blink state. Pose-specific hands are static authored attachments: callers should select them only for a matching weapon/action state. This API does not independently preserve grip swapping or other animated subparts inside a replacement texture.

This interface only provides attachment plumbing. It does not declare authored pose art, select a pose from player state, or establish visual/gameplay acceptance. Pose sources still require part-ownership, normal/glow, both-facing, armor-state, transition, and native Forward+ review.

## Authored bind pose and native mesh attachments

A replacement entry may use `mesh` instead of a rigid sprite. The pose then requires a complete `bind_pose` dictionary for **every existing bone**, with Bone2D-local Transform2D components `[xx, xy, yx, yy, ox, oy]`. These transforms describe the already authored source pose; they are not an extra animation to apply to its pixels. Selection temporarily changes the skeleton's bind rests without moving its current bones. Clearing selection, or switching to a sprite-only pose, restores the original rests. Current animation transforms remain the caller's responsibility.

Each mesh contains `vertices` and `uvs` as numeric pairs, flat explicit `triangles` indices, and `weights` entries `{ "bone": "existing_bone", "values": [weight_per_vertex] }`. Vertices are in Skeleton2D-local coordinates **before** the character root's translation, scale and facing flip. UVs are native texture pixels. Mesh entries reject sprite `offset` or `rotation`; they attach directly to the skeleton and must not inherit another bone transform. Texture metadata, matching normals/glow, armor counterparts and logical slot visibility retain the rules above.

Validation rejects missing/nonfinite/singular binds, native float overflow, UVs outside the texture, incomplete/degenerate/unreferenced topology, unknown or duplicate weight bones, invalid weights and sums other than one. JSON-decoded integral numbers are accepted as triangle indices after numeric validation. Each mesh supports one to four bone influence arrays. A pose must fit the existing **500 logical mesh vertex** budget: unreplaced base meshes plus all mesh alternatives in that selected set, including its hidden damage counterpart; glow companion geometry is excluded as in the base policy. Other cached sets are not counted as simultaneously active geometry.

For adjoining pieces, use corresponding source coordinates, vertices and weights at their seam; keep each limb's pixel ownership independent. The compact NE-222 front-knee control uses 25 vertices per piece without changing its source RGBA or alpha thresholds. This is a localized control, not approval of a whole pose. Missing anatomy requires authored source correction, not a wider mesh or opacity patch.

`Polygon2D.skeleton` resolves relative to the polygon, but **its bone weight paths resolve relative to Skeleton2D** ([Godot 4.7 implementation](https://github.com/godotengine/godot/blob/4.7/scene/2d/polygon_2d.cpp)). Verify actual native rendering: valid-looking CPU paths can otherwise collapse every weighted vertex. Preserve failed captures as negative controls. Run both facings, native/game and 3.4× close-up scales, 120 frames per schedule, the unchanged one-pixel seam checker, material/normal/glow review, damage transitions and whole-body anatomy separately. A seam-only unshaded capture cannot approve lighting, full-body movement or gameplay feel.

Visible native pose meshes contribute to `visual_bounds()` and AnimAudit's existing `mesh_fold` metric through the same CPU reconstruction of their current bone weights. Hidden alternatives and glow companions are excluded. Bounds apply the character root transform once; the fold metric compares triangle orientation against the authored source geometry, retaining the existing limit. The regression includes a deliberately reflected mesh with no legacy limb meshes, so missing native geometry cannot silently pass.

This fold metric does not measure native-mesh narrowing or compressed triangle area. Keep the existing legacy `limb_pinch` checks and separately inspect native source coverage, alpha seams, compression and whole-body anatomy; a zero fold fraction alone cannot approve a pose.

## Authoring a pose set from a character spec (NE-222, 2026-10-12)

Rigid pose pieces no longer have to be written into `character.json` by hand. A character spec may list them and `cut_layers.py` cuts
and registers them with every other texture:

```json
"pose_parts": {
  "sit": {"parts": ["leg_upper", "leg_upper_dmg"]},
  "crouch": {"same_as": "sit"}
}
```

Each listed name is an existing spec part. Its pose picture is `<work>/poses/<pose>/<part>.png`: a full-canvas layer of `base_rgba.png`,
registered on the same joints in bind orientation, so the part's own definition (mode, pivot, bones) cuts it. The texture is named
`<part>_<pose>`; one entry per use of the part is written (`slot` = the use's name, same bone). A part with a torn layer needs its
`_dmg` counterpart in the same list or the rig rejects the set. `same_as` shows another pose's pieces. The first production set is
Rin's seated hip and thigh (`art_src/characters/rin_sit/`).

`NpcAnimator` selects the set named like the current NPC posture once a posture transition is half way, and clears it when the
character leaves NPC poses; a skin without that set keeps its base parts (`CharacterRig.has_pose_parts`). Player states (the rifle
kneel) do not select pose sets yet. `tools/comfyui/rig_reference.gd` draws only the piece the rig selected.

## Pose-local draw order

An optional numeric integral `z` on an alternative entry defaults to its base slot's order. It is finite and bounded by the existing `WorldLayers.CHARACTER_MIN_Z..CHARACTER_MAX_Z` actor span; it cannot expand the actor group or change another character's layers. The whole set is rejected before construction if any entry is invalid. Clearing the pose restores the unchanged original base slot. Sprite and mesh alternatives use the same validation.

The cutter accepts `pose_parts.<pose>.slot_z` keyed by logical slot, within that skin's existing source range. It clones aliased pose entries before applying overrides, preserving the source pose and inherited defaults. This permits a seated near trouser thigh to pass under its shirt without changing its standing order. It does not fix duplicate source ownership: Ali also needs a sit-specific pelvis without the standing trouser cap. See [Ali source and native evidence](../../pm/Nest-Egg/attachments/NE-218-ali-seated/README.md).
