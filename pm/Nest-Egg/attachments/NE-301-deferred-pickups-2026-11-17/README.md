# NE-301：延後生成的掉落物

原本先建立 Pickup，再把 add_child 排在可能先被釋放的父節點上；父節點同格離場會取消這個呼叫，但還沒入樹的 Node 不會自動 free。這次沿 Pickup 基底使用靜態 deferred 交付與 parent／child WeakRef，失效或離樹的 parent 只回收沒有其他 owner 的 child；已 free、已排刪除或已改 owner 的 child 不再接管。沒有新增 autoload、pool、全域 pending 表或每影格工作。

## 最終來源與範圍

純隔離基準 aae101cfc85b192af9558d5b38d250aea4f1e726，`work/official-source-before.json`／after 與 `frozen-candidate/` 保存五份精確 bytes：Pickup 基底、Enemy、Level、既有 FxMeleePickupsSuite 及新增永久回歸 helper。產品只有 21 行共用交付與 4 處呼叫替換；金額、機率、位置、資源設定、拾取與持久化規則不改。

已核對全部 add_child.call_deferred 呼叫：只處理 Enemy 的信用點／補給、Level 破箱的信用點／物品。其他 minion、頭目可投擲箱、lift rails 是其他種類的生成，這次未改，不聲稱全專案所有延後物件都由本票修完。

BG-32 之後另有預載提交；本票正式測試與原生都明示純 AAE epoch，不冒稱最新 main 全部 bytes。底圖、rig、光照、劇情及預載不在五份產品差異內；最後整合另核對當前 main。全部原檔用本附件 `.gitattributes` 的 `-text` 保存，避免 CRLF 改變原 SHA。

## 原版與候選的實際入口

`raw/corrected-original-controls` 和 `raw/static-prototype-controls` 各 12 個獨立 Godot 程序：credit（真正 Enemy._drop_credits）、health（真正 Enemy._try_drop）、box（真正 Level._on_breakable_broken），分別 parent 存活／同格釋放、等待 deferred／frame 0 即整樹 SceneTree.quit。小型 Enemy 子類提供有效 idle FSM，使用已有 ch1_inspector VFX id；Level 子類僅關掉無關完整世界建置，但實際呼叫繼承的生產掉落方法，接收 parent 真入樹。

| 原碼條件 | 原碼結果 | 候選結果 |
|---|---|---|
| parent 存活，正常等待 | 三來源均 orphan 0→0、自然 exit 0、EOF clean | 相同 |
| 同格 free parent，再等待 | credit 0→1、health 0→1、box 0→2，自然 exit 1，保留完整退出診斷 | 三來源 orphan 0→0、自然 exit 0、EOF clean |
| parent 存活，frame 0 整樹 quit | 三來源自然 exit 0、EOF clean | 相同 |
| 同格 free parent，frame 0 整樹 quit | **自然 exit 0，但完整 EOF 有 RID／ObjectDB／resources，嚴格 gate 必須拒絕** | 三來源自然 exit 0、EOF clean |

這是實際退出程序，不是等兩個 frame 再把 parent free 的情境當作 quit。保留原自然退出碼，不把原版 quit 的 0 改寫成 1。本次邊界證明靜態交付可在退出時清理後，未添加 tree-exit cleanup 機制。

更早的 BG-32 最小控制在 `initial-bg32-drop-controls/`，包含真正 Stray Node ID 與 source。當時 EnemyData 的預設 id 會印 missing VFX ERROR、空 FSM warning；孤兒觀測仍存在，但不得將那些 log 稱為 clean。修正 fixture 後才有上表同一版來源的十二例。原碼 snapshot 和 candidate-restored SHA 都保留，沒有改掉原始失敗。

## 永久回歸與負控制

既有 FxMeleePickupsSuite 共 87 checks 通過；新增 helper 覆蓋重複排入只 ready 一次、child 早已 free／queued／換 owner、原 parent free／queued／離樹、真 physics body_entered 中尚未加入而 callback 結束後才交付，以及實際 Enemy／破箱入口的信用點、補給、武器、消耗品數量／位置／真正拾取一次。child 的弱引用與原 instance ID 直接用來檢查釋放，不只量最後畫面。

同套件原 `_test_pickup_kinds` 只問 getter、卻 new 六個 Node 後沒 free；保留相同種類／顏色斷言並正確收尾。第二輪 87/0 仍有六個舊 fixture Area、16 ObjectDB、8 resources 的紀錄保留；第三輪修 fixture 後 87/0，完整 EOF 無這些診斷。既有 test_no_such_attack 的刻意容錯 ERROR 仍保留，沒有更動 test_filters。

`raw/omit-cleanup-control` 只故意拿掉延後交付中 parent 失效分支的 child.free：同 87 checks 出現 14 failures、自然 exit 1；完整壞來源與 finally 恢復 SHA 保留。這個負控制會拒絕洩漏，不能用正常視覺或退出 0 冒充通過。

首輪 WeakRef 推論為 Variant 被 warnings-as-errors 擋下，原 parse log 保留；修成明確 WeakRef。那次程式沒有自然跑完，只停止這次自有的兩個 Godot 程序，不列成通過。

## 9070 XT 真實畫面

正式畫面採 `raw/native-fourth/`，Godot 4.7.2、RX 9070 XT、Vulkan Forward+、HDR 2D，9 checks／0 failure、自然 exit 0、完整 EOF 無 ERROR／leak。三張 1280×720 PNG 原 bytes 保留；主票公開圖片也來自第四輪。

受控建立正式 ch1_street Level，使用兩份真正 grunt 資料複本呼叫生產掉落方法，真正箱子的 broken signal 走 Level 物品入口。拍完後只釋放兩個展示敵人，讓 player 以 move_right／真 physics body overlap 收集：credits 0→17、health 5→7、med 0→1，三個原 Pickup weak reference 全 null。沒有直接呼叫 pickup._on_body_entered 來冒充這段原生收集。最後畫面自然顯示既有街道教學泡泡，原圖未遮改。

這是受控正式 Level 功能見證，不是完整 Main、自然通關、真人手把或效能基準。相機會隨真移動前進，不把三張不同位置稱作相同像素前後對照。沒有把敵人資料複本的測試金額／機率寫回正式資產。

第四輪顯式 APPDATA／LOCALAPPDATA／XDG 都在 `D:/NestEggVerification/evidence-20261117/ne301/native-isolated-profile`；summary 同時記實際 user_data_dir、三產品 SHA 與工具自身 SHA，可與原 gd 完全核對。第三輪雖功能通過，launcher 未明確隔離 profile，故原圖／log 保留但不作隔離證明，也不聲稱個人 profile 逐檔未變；沒有查看或還原個人資料。

外部 scene 避免在已凍結的專案中新增 untracked probe。最早兩次嘗試 `--script` 自訂 SceneTree，依賴編譯缺少 autoload globals；失敗 log／來源 epoch 都保留，僅停止自有失敗程序。改正常外部 .tscn 後 autoload 全域與實際功能皆成功。`raw/native-source-snapshot.json` 是第三輪之後的來源 metadata；後續新增 profile／內嵌工具 hash 的第四輪 bytes 不同，用 `raw/source-epoch-aliases.json` 對回第三輪原 bytes，不改原 SHA 假裝相同。

## 正式受影響測試與可攜核驗

官方 `tools/run_tests_changed.sh aae101cfc85b192af9558d5b38d250aea4f1e726`，SHARDS=2、76 組，原 log 在 `raw/official-aae/`；結果與自然退出碼以完整 console／兩 shard／exit.txt 為準。after source guard 和 final manifest 都寫好才會發布 final-ready，不把封裝中的檔案存在視為已完成。

正式結果：97,199 checks、新失敗 0、已知失敗 0、1559 秒、自然 exit 0；兩分片為 49,591／47,608，五檔 bytes／SHA、HEAD AAE、dirty 清單前後完全一致。分片 0 完整 EOF 無後續診斷；分片 1 仍有 1 CanvasItem、9 ObjectDB、5 resources 退出診斷，完整尾段記於 `work/official-result.json`。未做逐 ID 歸因，不稱全部 headless raw 無 ERROR，也沒有改 test_filters 豁免新失敗。獨立 87 項套件（只保留既有刻意缺招式 ERROR）、12 候選微控及第四輪原生的嚴格 EOF 結果分開列示。

執行 `python verify.py` 可只讀本附件，重算原輸出／manifest、五份來源、原版與候選 12 例、真 quit 的嚴格 EOF、固定負控制、87 項永久套件、9070 XT 原生效果／profile／tool hash、三 PNG、正式結果及前後 source guard。只用 Python 標準函式庫，不需 GPU 或 Godot。它會拒絕尚未 final-ready 的封包。

重跑 CPU 微控時將 `raw/frozen-fixtures/ne301-lifetime-probe` 恢復到自己的 worktree 相同 res://work 路徑，三個 `--case=credit|health|box` 配 `--keep-owner`／`--quit-before-deferred`，每例獨立 process/profile。原版對照 driver 在 `work/run_original_controls.py`，僅在自己的乾淨隔離使用；先備份候選且 finally 精確還原。正常退出 0 仍須掃完整 EOF，不能略過原版 quit 的洩漏。

重跑原生需在自己的實測來源 snapshot 中以正常主 SceneTree 載外部 `native_scene_witness.tscn`，將其外部 gd 路徑改成自己的絕對位置，設定全新隔離 profile，再用 gpu_lock 執行 Forward+ Vulkan、`--out=<絕對新目錄>`；不可用失敗的自訂 --script SceneTree 入口。路徑調整會改工具 bytes，新的 tool SHA 應如實記錄。
