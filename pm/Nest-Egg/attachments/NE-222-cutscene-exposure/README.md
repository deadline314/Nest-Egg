# NE-222 cutscene exposure evidence

This packet records a bounded lighting/exposure correction in the clinic cutscene. It does not establish that Rin's kneeling pose, hips, clothing seams, or all scene lighting pass their separate visual requirements.

## Native clinic comparison

[`NE-222-clinic-fill-before.png`](../../images/NE-222-clinic-fill-before.png) and [`NE-222-clinic-fill-after.png`](../../images/NE-222-clinic-fill-after.png) in `pm/Nest-Egg/images/` are byte-for-byte copies of the native 1280×720 captures. [`NE-222-user-hip-kneel-latest.png`](../../images/NE-222-user-hip-kneel-latest.png) is the user's original 1920×1080 RGB attachment, also copied unchanged; it is a visual reference, not a capture from the test scene.

The paired reports use the actual clinic scene and Forward+ HDR rendering (Godot 4.7.2, Vulkan, RTX 4070 SUPER). The diagnostic camera is at Y=205.0. In the before case, the legacy level-fill path remained enabled: actor fill/cap `1.0/0.5` followed level fill `1.0`, then `4.0`; the capture report is **FAIL**. In the after case, the legacy override is disabled and the actor uses fill/cap `1.0/0.2`; level fill `1.0` and `4.0` both report actor fill `1.0`; the capture report is **PASS**. The older full-bright fill baseline is retained and reports **FAIL**.

This framing is diagnostic. The shipped camera Y=221.4 can crop hair, so these images do not prove shipped-camera framing. They do not prove hip/knee anatomy, clothing articulation, or the whole cutscene.

## Isolated light response

The isolated probe holds a Sprite2D and Polygon2D receiver, normal map, CanvasModulate, fill, and light cap constant while testing DirectionalLight2D and PointLight2D at energies `0`, `0.15`, and `0.75`. The baseline report fails the point-light response: both receiver types remain at linear luminance `0.507324` at all three energies. The candidate report passes this bounded monotonic-response check: both point receivers measure `0.033081`, `0.176392`, and `0.478516`; directional receivers also respond. The baseline and candidate records pin different shader SHA-256 values, listed in `manifest.json`.

The retained raw reports label the assigned CanvasModulate `Color(0.2, 0.2, 0.2)` as `canvas_modulate_linear`; that label is inaccurate. It is the assigned color, not a measured linear ambient value. The actual zero-energy HDR readback is `0.033081`; receiver samples and the gray reference are measured linear values. Raw reports are preserved unchanged.

The retained lamp captures report white-pixel ratios `0.012`, `0.000`, and `0.001` for gaps 12, 40, and 80, with sampled head-region peaks `9.39`, `5.39`, and `7.80`. Those sampling rectangles include lamp/background/glow pixels; they are not a pure hair highlight measurement and do not prove the entire lighting field.

## Regression evidence and rejected runs

`affected-tests-summary.log` and its six shard logs record the isolated changed-suite run: 67 groups, 46,532 checks, zero new failures, zero known failures, 228 seconds. The `cpu-baseline-valid-rejected.log` is a separate earlier run with 222 CutsceneSuite checks and two failures in the fill/cap assertions; malformed-scene ERROR output in that run was intentional test input. It is preserved as a failing baseline, not presented as a clean run.

Files prefixed `rejected-` retain earlier invalid or superseded attempts. In particular, the early clinic probe stopped on a script error; the unisolated light baseline included another active GPU job; and the first light harness expected the wrong readback format. These attempts are indexed in `manifest.json` and are not acceptance evidence.

## Provenance and limits

- Working tree HEAD at packaging: `7e3289808d00e339c0662f26d1ab61c02de0f9d6`; the shared checkout also contained concurrent unrelated modifications. The relevant current shader and probe source hashes are in `manifest.json`.
- Captures use Godot `4.7.2.stable.official.ed1daf0bf`, Forward+, Vulkan, NVIDIA GeForce RTX 4070 SUPER. Clinic viewport: 1280×720, HDR image format 14.
- The before/after native reports and PNGs are copied unchanged. The isolated light probe's reports and representative PNGs are copied unchanged. `manifest.json` lists byte counts and SHA-256 for packaged files and linked project images.
- A passing exposure probe is limited to these scene and receiver configurations. It is not a full-lighting, anatomy, pose, animation, or NE-222 completion claim.

## Primary references checked

- [Godot CanvasItem shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html): custom light functions receive `LIGHT_ENERGY` explicitly.
- [Godot 4.7 canvas shader implementation](https://github.com/godotengine/godot/blob/4.7/servers/rendering/renderer_rd/shaders/canvas.glsl): point-light energy is passed independently of light RGB.
- [Spine: rigging new poses](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial) and [mesh weight workflows](https://esotericsoftware.com/blog/Mesh-weight-workflows): pose-specific art and deliberate bindings support the separate anatomy work; this lighting packet does not accept that art.
