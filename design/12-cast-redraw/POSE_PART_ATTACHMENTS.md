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

This interface only provides attachment plumbing. It does not declare authored pose art, select a pose from player state, change canonical rest bones, or establish visual/gameplay acceptance. Pose sources still require part-ownership, normal/glow, both-facing, armor-state, transition, and native Forward+ review.
