# NE-79 organic combat evidence

This packet records one bounded combat route for the enforcer (`shield_rusher`) at source revision `212768fa4a98e9db5bb1b3f4c067ef6027c7547d`. It is evidence for the actual shield, AI telegraph/charge, Player Hurtbox, and real Player projectile path. It does not complete the ticket's eight-action/joint-art review or establish full visual quality.

## Recorded result

- CPU/headless NE-79-only preflight: 13 checks, 0 failures. See [CPU log](cpu-enforcer-preflight.log).
- The public replay was also run headless with the dummy audio driver: 13 checks, 0 failures. See [public replay log](public-replay-cpu.log) and the copied [CPU manifest](public-cpu-preflight.json).
- Native Forward+ readback: 16 checks, 0 failures, Godot 4.7.2-stable, Vulkan 1.4.351, NVIDIA GeForce RTX 4070 SUPER. See the exact [native log](native-forward-plus.log) and [raw native manifest](native-enforcer-preflight.json).
- Three 1280×720 captures were saved after the real event, with simulation paused for two render frames and matching before/after state: [windup](../../images/NE-79-organic-combat/NE79_enforcer_windup.png), [charge skid](../../images/NE-79-organic-combat/NE79_enforcer_charge_skid.png), [rear-side hit](../../images/NE-79-organic-combat/NE79_enforcer_rear_hit.png).
- In the recorded path, a real front-side Player pistol shot was blocked (enforcer HP 8→8; ammo 12→11), the natural charge/contact reduced Player health 12→6, and after the Player was repositioned to the rear side a real projectile reduced enforcer HP 8→7. The rear-side reposition is a controlled test setup; it is not reported as organic player movement.

The rear-hit image is a full gameplay-context capture. The HUD overlaps the enforcer's feet, so it is not joint-art evidence.

## Replay

From the repository root, provide a fresh empty absolute output directory and the revision label. The script refuses a non-empty output directory and writes a JSON manifest there. `--head` is a label for the run; get it from the checkout you are testing.

```powershell
$head = git rev-parse HEAD
$out = 'D:/NestEggVerification/ne79-organic-replay-new'
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . 'res://pm/Nest-Egg/attachments/NE-79-organic-combat/replay.tscn' -- "--head=$head" "--out=$out"
```

This replays the CPU path without taking viewport readbacks. For native Forward+ screenshots, run the same scene without `--headless`, add `--capture-images`; those captures are written beside the manifest. Use the repository's shared GPU lock and a different fresh `--out` directory. Native screenshots in this packet are the already-completed root-owned capture, not produced by the dummy-renderer replay. The run manifest pins the character definition, rig definition, all configured enforcer part textures and their normal/glow companions, plus the combat data and callers.

Verify the archived evidence and its one-byte corruption negative control with:

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' 'pm/Nest-Egg/attachments/NE-79-organic-combat/verify.py' --self-test
```

`evidence-index.json` pins image dimensions/hashes, logs, and the raw event manifest. PNG bytes and native JSON are copied unchanged; the packet's `.gitattributes` keeps log bytes from line-ending conversion. The verifier also checks screenshot-to-event mapping, frozen simulation state, and the recorded shield/charge/rear-hit results.

## Limits

This packet covers the NE-79 bounded route only. It does not validate all eight preview actions, every joint, every armor-loss stage, all facing/weapon attachments, or complete ticket acceptance. The ticket remains in progress; its unchecked eight-action/joint-art condition remains unchecked.
