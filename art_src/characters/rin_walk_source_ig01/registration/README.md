# Source material-axis registration control

This packet corrects the four terminal material axes in a **source-only** Rin candidate. It is not registered in the game. The accepted standing source remains unchanged, SHA-256 `401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9`.

The formal hand images point approximately along local +X, while the boot's ankle-to-toe material vector points at 45 degrees. Assuming every material points along a bone's local +Y turned the new hands sideways. With the actual formal texture pivots, the rejected angular errors are 88.204 degrees (mechanical hand), 88.635 degrees (natural hand), and 45 degrees for each boot.

`rejected-bone-axis-bind.json` preserves the previous CPU proposal, including its ownership ledger, measured source pivots and unresolved branch geometry. `build.py` uses the unchanged production bone hierarchy, actual 1.4-radian hand setup rotation, formal texture pivots and explicit material endpoints. It checks pinned source/rig/character hashes, opaque endpoint pixels, four wrong-axis controls and a complete 20-bone FK reconstruction. The new bind only changes terminal material orientation. The four nonprimary shoulder/hip/coat branch residuals remain recorded and unresolved.

Rebuild with the project's configured Python:

```powershell
python art_src/characters/rin_walk_source_ig01/registration/build.py
```

The [native control](../../../../pm/Nest-Egg/attachments/NE-222-material-axis/README.md) renders the actual mechanical-hand crop through production Skeleton2D paths. It separately shows the original source, rejected sideways hand and corrected hand at 1:1. No cuff/wrist seam, complete outfit, normal/glow, anatomy, walking, transitions, performance or gameplay acceptance follows from this isolated control. These files must not be copied into `character.json` as an approved walking set.

This follows the preparation and alternative-bind workflow in [Spine's official new-pose tutorial](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial); source registration and rendered weight checks remain separate from final animation acceptance.
