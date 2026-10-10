# NE-222 visible walk-source hand and boot cuts

This progress delivery preserves the liked standing source SHA `401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9` and all formal character art, rig and movement data. It publishes two corrected **visible source cuts** for the separate walk candidate. They are not selected in the game and cannot approve full-body, moving joints, lighting, damage or gameplay.

Rebuild and exact source-coordinate ownership decisions: [author parts](../../../../art_src/characters/rin_walk_source_ig01/author_parts/README.md). The source remains the immutable C34 candidate, SHA `3af1fa39fd7325c92ed8f1dd75562a98f7636ce723f619643a8eb4235ed71c75`. No inference or SAM rerun occurred.

Root viewed the entire corrected hand/boot outline and all 14 tiny disconnected components in `island-context/`. The explicit 16 excluded source pixels are sampling halos; there is no blanket alpha threshold. The source thumb, cuff, lace knot and magenta outsole remain, as do connected partially transparent contours. Published crop dimensions are native; no image was resized. Thirteen material-omission/foreign-owner fault controls reject one-pixel mutations. Two exact rebuilds match; raw output is in `build.log` and `determinism.log`.

## Native diagnostic capture

The existing viewport readback helper is reused. A separate small Godot project displays each cut at exactly 1:1 on black/gray/white. Native Godot 4.7.2, Forward+, HDR2D SubViewport, RTX 4070 SUPER, shared GPU lock, Comfy stopped. `capture.log` records exit 0, no ERROR; root viewed the complete image. This is a material/alpha preview, **not a gameplay screenshot or a rig acceptance**.

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path pm/Nest-Egg/attachments/NE-222-walk-visible-parts/native -- --root=<absolute repository> --out=<absolute PNG>
```

![Native visible-source preview](../../../images/NE-222-walk-visible-parts.png)

The two source cuts remain separate from their wrist/calf underlayers. Their existence does not imply the jacket or body are fully segmented, or that a new walk pose has been installed. NE-222 remains in progress under its unchanged acceptance conditions.
