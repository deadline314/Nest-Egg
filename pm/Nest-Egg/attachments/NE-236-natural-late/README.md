# NE-236 自然晚進目標證據

本次只補強驗收與取證，不改角色／舊姿勢、Main／Story、共享 Fx 或存檔。成長功能已暫存，因此獨立測試實際使用 NE-236 已交付 runtime，沒有借用 NE-237 未交付邏輯。

固定基準：`cd0d454f6211fb83e1ab06e183257b1fb469c726`。正式 fetch/rebase 整合基準：`f2646d1f7de8458b3cc9eb19834db4e051a72628`。

- [第一次失敗摘要](changed-first-console.log)、[完整失敗 raw](failure-shard-0.log)：scratch `.gd` 備份具有相同 class_name，fresh import 登記了錯誤類別；0 checks，腳本錯誤，exit 1。改為純文字備份並重新匯入後重跑，沒有修改 runner／selector／known_failures。
- [成功摘要](changed-fixed-console.log)、[完整成功 raw](success-shard-0.log)：`SHARDS=1 tools/run_tests_changed.sh cd0d454f6211fb83e1ab06e183257b1fb469c726`，98 checks、0 new/known failures、exit 0。
- 自然回歸建立兩個真 Enemy/Hurtbox 和一個真的跑 physics 的獨立第三節點。首擊造成傷害並實際 freeze 攻擊者；仍 ACTIVE 時移入晚目標，完全由 Player physics sweep 掃到，不呼叫 `_melee_hit_pass`、不提早 thaw。
- 晚目標 999→997，單一 damage event；自身速度 `(80,-24)`、stun `.45`、flash `.08`。真 attacker 保留，freeze_attacker=false，攻擊者恢復 physics 且不再 freeze。第三節點 9→30 ticks，完整自然收招後晚目標仍只受一次傷害。
- [真 Forward+ 原始輸出](forward-plus-first.log)：既有 gpu_lock、正式單次審查 Xvfb，Godot4.7.2 Forward+／llvmpipe 軟體 Vulkan／Dummy audio。實際自然 late hit 的 knockback80、stun.45、第三節點48→64；接觸圖於下一個 draw 已是 RECOVERY，沒有把它當 ACTIVE 瞬間或人工實戰。第二張是自然收招完畢。
- [source diff](source.diff)、[來源、raw 與圖片校驗](sha256.json)。新增回歸原先所針對的舊邏輯失敗保留在 [前階段 raw](../NE-236/regression-before-shard.log)。此處不存在新的 runtime 修正。

原始引擎、刻意容錯與退出診斷完整保留；exit0 不等於無 ERROR。圖片不證明人工手把、硬體 GPU／HDR 或聲音人工試聽。

## 最新主線整合

`SHARDS=1 tools/run_tests_changed.sh f2646d1f7de8458b3cc9eb19834db4e051a72628`：[摘要](changed-integrated-console.log)／[raw](changed-integrated-shard-0.log)，98 checks、0 new/known failures、exit0。晚目標相同速度80／stun.45，第三節點9→31。

含主線續玩通知順序與環境更新後，Main／RunSave／HitReaction／Environment 四組：[摘要](integrated-console.log)／[raw0](integrated-shard-0.log)／[raw1](integrated-shard-1.log)，8,160 checks、0 new/known failures、exit0。全數實跑，沒有在 commit 後以空 diff 代稱測試。
