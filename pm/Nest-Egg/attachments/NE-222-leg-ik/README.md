# NE-222 leg IK regression evidence

本次交付是共用腿部 IK 的角度表示修正。正常彎膝跨過 atan2 分支時，局部角度原先可能落到 -4.57 radians；現在取等價的最短角差，端點、腳掌方向、骨長及父鏈保持不變。使用 Godot 原生 [angle_difference](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-angle-difference)，沒有改 AnimAudit 門檻。

`capture.tscn` 沿用既有姿勢定位工具與固定骨長可行性資料 `feasibility-kneel-scan.json`，輸出 [原生參考與幾何記錄](../../images/NE-222-leg-ik/)。它使用正式 `_reach_leg`，移除了私有小樣的手動角度 wrap。這是新素材製作的骨架參考，不會改變玩家目前的姿勢選用，也沒有載入未接受的 22292 候選。原有臀部輪廓、手與其他接縫不能因此算通過；source contact 的 .03 skeleton-unit assertion 是此參考工具的測量，不能代替一像素接縫驗收。

原生擷取：Godot 4.7.2、Forward+、RTX 4070 SUPER，兩面向各 1×／23.78×，四張 PNG，最大原生 1198×1049，exit 0 無 SCRIPT ERROR，見 [native log](ne222-leg-ik-native.log)。固定基準 e6c7424e 的 [受影響測試](ne222-canonical-ik-changed-tests.log)為 39,445 checks，零新／已知失敗；這是 selector 挑選的 53 群，完整套件交給 CI。選單中的 EnemyArtDeliverySuite 尚未註冊，不宣稱它執行。

同步 main 的槍彈修正 727dd8e1 後，補跑 FxUpgradesSuite、PostureSuite、RigActionsSuite、FeelSuite：[合併回歸](ne222-ik-main-merge-tests.log) 3,220 checks，零新／已知失敗，18 秒。

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method forward_plus res://pm/Nest-Egg/attachments/NE-222-leg-ik/capture.tscn
```

- Scope: CPU-only `PostureSuite`, Rin's actual `humanoid_tall.json` 20-bone rig; production rest offsets and parent links are snapshotted and verified unchanged.
- Existing-suite baseline: root reports `PostureSuite` passed in earlier NE-90/main runs (684 + 3363 checks); per root instruction, it was not rerun before adding this regression.
- Initial regression RED, before the production `_reach_leg` fix: `posture-red.log`, exit code 1, 100 checks / 2 failures. Failures were local rotations outside `[-PI, PI]` and a negative local knee bend. Endpoint and foot-angle checks passed. This is an initial test version (single final-state AnimAudit sample), retained only as evidence of the initial regression.
- Current regression: samples AnimAudit's existing `_measure` helper for every one of 72 IK cases (four quadrants plus both sides of the atan2 branch, front/back chains, facings ±1, and parent rotations 0/±2.7). A manually forced `leg_front_lower.rotation = -0.2` remains the negative control against the unchanged `AnimAudit.LIMITS.knee_hyper` value.
- Current green after root's three `angle_difference` changes: `posture-green.log`, exit code 0, 101 checks / 0 failures.
- The CPU regression logs alone contain no render/GPU checks; the separate native capture above is recorded independently. The regression only proves fixed-length skeleton-space IK geometry, canonical local angles, foot orientation, and preservation of the existing knee audit signal.
