# NE-228 clearance — independent 24-image visual review

Reviewed 2026-10-10 using `view_image` for every original clearance PNG. CPU/file reads only; no engine, Git, repository or image edits. The paired delivered originals were reviewed previously; this pass also reopened delivered-720 right crouch, delivered-1080 startup, and delivered-wide right stand/left crouch for direct comparisons. SHA256 and original PNG dimensions for all 24 new images, 24 baseline images, logs, exit files and seven source files are recorded in `VISUAL_REVIEW_CLEARANCE.json`.

**Bounded acceptance:** the previously reported cyan-leader crossings through health/guard, ammunition and ChapterCard text are visibly fixed in these captured poses. No new prompt-frame/font clipping or face obstruction was found in the 24 images. This accepts the captured UI clearance and text fit, not completion of the chapter, continuous combat or the entire UI ticket.

| Profile | Original images inspected | Visible result |
| --- | --- | --- |
| 720, 1280×720, text 100% | All eight | Right stand/crouch leader has a visible gap around health/guard and the complete ammo row; lower span still ends at the original sign. Left stand/crouch keeps the full clear leader and target dot. Dialogue, object and two-line radio text are complete. |
| 1080, 1920×1080, text 120% | All eight | Same right-pose gaps, left-pose target retention and complete movement instruction. Startup leader stops above the pink chapter title and resumes below the subtitle without drawing through either. NPC header/body/portrait and OBJECT header/body fit. Three-line radio includes the final `換了。` without clipping. |
| wide, 2100×900, expand, text 120% | All eight | Same visible line clearance and original target association. Startup chapter title/subtitle gap is visible. All prompt frames remain inside the expanded viewport, with complete text. Full modal reading surfaces, speaker portrait/name and all three radio lines fit; radio stays clear of actual heads. |

## Actual pixel findings

The right-facing cyan line is interrupted rather than moved to another object. At 720 right crouch, its former straight path at approximately physical x286 now stops above the pips and reappears below the ammo/infinity row, reaching the dot immediately over the movement sign. The 1080 and wide pictures show the same actual gap. The gap also clears the white guard bar, not just the cyan pips. No line stroke was seen crossing Rin's visible face, torso, hands, pistol or legs. Left-facing stand/crouch still shows the original unoccluded continuous line and dot, with no disconnected replacement target.

The 1080 startup before/after pair is a particularly useful independent case: the delivered original had a line through the pink umbrella/title and pale location text. In clearance the upper segment ends before that reading area and the lower segment continues beneath it to the same sign. Wide startup shows the same effect. Slight camera/aim/timing differences between runs prevent treating these as exact pixel-subtraction tests; the collision and its disappearance are nevertheless directly visible.

Every movement instruction is complete, including `移動 A/D，跳躍 Space（按久跳更高）`. Its cyan frame stays on-screen and above the nearby player/vitals. The compact pause cue retains its readable Escape cap/instruction at the actual viewport right. Empty hint boxes have not appeared in these pictures. Existing ammo icons/infinity mark and white energy/guard shell remain readable; this does not verify every possible ammo digit, ammo-empty transition or low-health animation.

NPC dialogue retains the deep blue stepped frame, yellow name tab and old-K portrait; body text is complete. The warm grey OBJECT surface has its proper reading title and no person portrait, with complete body text and no added black bars. Radio retains a distinct cool blue panel, cyan portrait accent, purple speaker header and full body text. At 1080 its bottom edge is only about 5–8 physical pixels above the pictured actors' heads: no face is covered in this image, but that proximity is not a general continuous-motion guarantee. Wide composition has a larger lateral separation from the actors.

No competing full NPC ambient line or WorldPrompt invitation is visible over the NPC/OBJECT modal body, and timer/credits are hidden in those two modal captures. Timer/credits and ammo may remain during passive radio; they do not intersect this radio panel. Small yellow NPC `⋯` and cyan `!` markers still exist in some modal/radio captures. They are a recorded residual, not proof of complete world-marker suppression. The Enter cue is blink-off at these captured instants, so these pictures do not independently prove its visible blink-on state or input behavior.

## Source and native evidence

The supplied `cloud-clearance-payload.json` declares base `82882bb455ad2d57a5904a6cfbdf6b9c8d6645fa`; its raw patch SHA256 is `45aa2b20388dcfe6596bd43356b073600467432e9595b8136f30c8896c09527c`. I independently checked the raw patch and all seven adopted source bytes against that manifest; all match. Manifest SHA256 is `cfb699a01a3dfcb7653d76348537a619bce89a47ddd6210b3707fe368f410870`.

All three corresponding logs identify native Godot 4.7.2, Vulkan Forward+, Intel Arc B580 and the isolated profile. Their exit files contain 0; the logs contain no ERROR/FAIL/Warning line. Actual stand/crouch captures use real Player physics and move_down input, not a manual crouch property or obstacle fixture. Observer geometry is supporting integration evidence only: this conclusion was made from the visible PNGs, not from recomputing the same clipping function. Root separately reported local UiScreens/WorldPrompt/AmmoTray 200 checks/0 failures; the cloud original changed-selector result was still pending when this review was written.

## Limits and existing capture-only artifacts

The authored old-K capture runs actual Level/NpcActor/Story UI without the full MainStage behavior, so Rin's retained pistol aim can point into the NPC's face in the dialogue/radio pictures. That visible existing capture-only limitation remains; the UI clearance patch does not solve it, and these images cannot establish normal full-Main dialogue posture or cinematic weapon lowering. No rig, pose, weapon or character artwork was changed or accepted by this review.

These 24 static captures do not prove continuously moving/combat art envelopes, low-health/pop/shake/parry/break Vitals behavior, all other weapons, arbitrary transformed parent layouts, or all unread ChapterCard/ambient-bubble lifecycle transitions. The late radio capture's absence of a startup card cannot establish preserved card lifetime by itself; separate real lifecycle tests are needed. The synthetic gamepad-glyph probe is not a physical controller test. This is neither human/controller acceptance nor a tutorial, chapter, Story-completion or production-capability claim.

No remaining blocking visual defect was found **within these 24 clearance captures**. Keep the above marker/blink/posture and dynamic-coverage limits in the release evidence.
