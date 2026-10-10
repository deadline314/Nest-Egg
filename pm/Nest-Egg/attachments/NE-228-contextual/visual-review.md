# NE228 delivered24-image independent visual review

2026-10-10. Root reports source a5efd3e48+sameUI. Viewed all24 original PNGs: delivered-720(1280×720/text1.0), delivered-1080(1920×1080/text1.2), delivered-wide(2100×900/expand/logical840×360/text1.2). Read each native log, which identifies Godot4.7.2/Forward+/ArcB580. CPU/view_image only; no engine/Git/repository/character-art changes. Wide tool preview resized to2048×878; SHA/dimensions refer to original PNG files. Inventory: `VISUAL_REVIEW_DELIVERED.json`.

## Actual result

The former blocker — crouching VitalsTag pips drawn through movement text — is **visibly fixed** in all three sizes. The instruction is raised above the complete visible health/guard tag. All12 actual standing/crouching left/right pictures keep prompt frame and glyphs clear of Rin's visible head, torso, hands, pistol and feet. Instructions are complete, and cyan leader points to the original movement sign rather than relocating to an unrelated point.

| Size | Pose pictures | NPC / OBJECT modal | Radio / compact hint |
|---|---|---|---|
|720 | Both standing and both crouching frames/text clear art, pistol and health text area. | Header/portrait/body intact; no full ambient dialogue, world invitation, timer/credits collision. OBJECT no black bars. | Complete2-line radio, faces visible, no chapter/ambient/invitation fragment; compact hint complete and clear. |
|1080/120% | Same visible separation, complete instruction at enlarged scale. | Enlarged speaker/object/body text intact; same suppression fixes. | Complete3-line radio including final `換了。`; panel's lower edge remains just above actor heads. Faces readable. |
|wide/120% | Same separation at expanded840logical viewport. | Full-width modal text/portrait fit; object retains no-blackbar semantics. | All3radio lines fit; heads clear. Compact pause cue remains at actual viewport right. |

NPC dark-blue portrait/tab, warm-grey OBJECT reading surface and cool-blue radio remain recognizably distinct. Short modal lines leave substantial lower/side space, but no new font clipping is visible. Native observer's reading-space intersections support the frame separation; the image itself supplies the actual visible evidence.

## Remaining visible residuals

**Leader path is not yet clear of all UI.** In right-facing standing/crouching images, the long straight cyan leader passes through the floating health/guard tag and ammunition row. Examples: physical x≈286 at720, x≈431–466 at1080; same phenomenon in wide. Text and health counts remain readable, so this is lower severity than the fixed glyph collision, but it is an actual residual. Reading-box intersection assertions do not test the leader segment. In the1080 bootstrap picture, the same long leader also crosses the chapter-card umbrella/title/subtitle region. A narrowly scoped segment-vs-obstacle clipping candidate is separately requested by Root; no fixed/native acceptance for that future change is claimed here.

Small yellow NPC `⋯` and cyan `!` markers remain in modal/radio pictures. They are not a competing full line and do not obscure a face, but total world-affordance suppression is not demonstrated. The NPC and OBJECT Enter cue happens to be blink-off in these captures; do not infer a missing continue action from one frame, and do not claim these PNGs visibly verify that key hint. Corresponding input/helper tests remain required.

Floating vitals stay near a fixed standing-head offset while crouched. This review accepts **separation from the prompt**; it does not judge the full tag's low-health/pop/shake/parry/break/health-change animation or all world effects. Player6px breathing margin is a presentation cushion, not a continuous-combat art envelope. Captured setup/equip/standing/crouching pistols cannot prove all weapons/hot-replacements/attack angles.

## Evidence limits

Root used actual move_down input and real Player physics for poses; log records floor/crouch/facing/pistol. No fixture obstacle or manual crouch assignment is inferred. Radio captures occur around8.8s after prior pose captures; absence of the startup ChapterCard is insufficient on its own to prove preservation of a still-live card. Meaningful native tween/unread-bubble lifecycle regressions must establish hidden clocks/remaining-time/same-line restoration and no extra completion. Source changes and screenshots are not Story/tutorial completion or capability evidence.

No physical-controller acceptance, human readability study, complete chapter, full UI-page or all changed-suite result is asserted. Original changed60groups was still running at Root's request. Existing unrelated character-part art is outside this UI review and was not altered.

## Bounded conclusion

Accept the24 captured **text/frame fit, actual standing/crouching art+weapon/vitals separation, radio local composition, material identity, compact hint and modal collision fixes**. No new body-text clipping or actor-face blocking is visible. Keep the leader-through-floating-UI/title residual explicit until its narrow patch and native picture are reviewed. This is not full-ticket closure.
