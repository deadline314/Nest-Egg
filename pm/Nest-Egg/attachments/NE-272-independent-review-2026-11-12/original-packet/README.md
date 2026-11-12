# NE272 獨立審查與脈衝應對補證

本包只包含 Git 原始物件、既有 CI、原三張 PNG，以及本輪四個自然引擎時鐘的無頭組件控制。沒有改 C 產品、永久測試、票或 Git index；沒有啟動 GPU，也不宣稱真人通關或實體控制器驗收。UI Codex v5 保持原 cb3a / a9fd。

## 結論與五條驗收

可供 Root 收尾 NE272。此前欠缺的「盾擋／跳過」專項執行證據已補；正式美術仍按票中明載的暫代範圍處理。本輪不把歷史票上的統計改寫成重新執行的結果。

| 條件 | 審查結果與直接證據 |
|---|---|
| 地面約 .7s、充電約 .8s、單束及擋／蹲／跳 | pump / insulation 的正式 EnemyData 分別 .7 / .8；原 Chapter3EnemiesSuite 檢查 ram 預兆至少 .6s、終點不超過亮線、實際 crouch 避傷／standing 中彈。新增 standing/crouch/shield/jump-v4 四程序 35/0，全部從原 idle 自然充電／鎖定／發射，不寫 FSM、telegraph、HP 或命中結果。離線 reader 另重算實際子彈穿越與真正格擋回呼。 |
| 正式戰鬥區與可繞、不鎖主線 | 九張 map 拼接後的地形／字元格，自 b649 與 CI 到 a4 逐 byte 的 rows 相同；pump 上橋 11..77/13 及入口階梯，mezzanine 照護步道 41..58/14 及兩側階梯仍在。三場 design `lock=false/wave_zone=false`。原套件實跑「上層 player 不觸發 pump、吊軌上方不充電」；這是資料與機制證據，沒有冒稱本輪從廣場自然走完兩條路。 |
| 遭遇上限與安全區 | 實際 map：pump 2 pump＋1 insulation、mezzanine 各1、gate_hall 1 Janus，其餘六區0。三個普通遭遇分別1/2/2，每場近戰／遠距各最多1；不是聲稱整個 viewport 永遠只能看到1近戰。Janus 資料 max_backup2 / max_alive3，原測試驗真生成上限；出生 offset -200/+220 與 pump 自然巡邏 ±80 不變。此安全規則不禁止玩家主動引誘追擊，票 Commit2 原文也保留「被引來時照常追」。 |
| NE97、資料批次調整 | 正式 chapter_rosters 的 ch3_clearwater 仍只有 pump_inspector / insulation_inspector / janus 與九區。產生器 `ENCOUNTERS` 單表給三場與 Janus；actual map 的五台巡檢器座標與該表一致。全章目前跨章身份0；不把 bomber 暫代外觀說成零外觀重用。 |
| 暫代外觀明列 | 票原文／目前資料都明列 pump 的 bomber 零件×1.6，insulation 的程式滑車與獨立 probe hurtbox；原圖也實際看得到兩種不同輪廓。正式排水機／滑車零件仍待角色組，不宣稱新美術已交付。此條驗收要求暫代列表，沒有另加原票不存在的硬體條件。 |

## 原來源與真正既有回歸

比較原提交 `0f66990f50cab43a73c9cd2921a270aaefbff747`、修正 `b649a7c21b4bc5d231e02007ca24bd2b4d9c7913`、真正實跑 CI 的 `ba37327fbe4e8a0f293b735f4a4e5aa6b58d2dfd`，以及固定 published `a4f2db7a81cd8c58bf8dea1afcdf499375dcba58`。最終 index 是 **66 個實際存在的 published 路徑**，不是整個遊戲來源。66 路徑的 CI 與 a4 都相同；D 中本 probe 引用且逐 byte 核對的51份 gd/json/tres 也與 a4 相同。各版本原 bytes 均在 ZIP。

兩 behavior、兩 EnemyData、insulation_pulse 在 b649→a4 完全相同。pump 在原0f後加自然巡邏 ±80；insulation 原0f→a4 不變。原巡檢器八個相關測試函式在 b649→a4 不變；整個第三章檔後來只新增 Janus config helper 呼叫，不能說整份測試檔從0f完全相同。0f→b649 間另合入 Janus 內容，因此79與145的歷史數字不能互相當相同來源。

產生器／map JSON／音訊／圖鑑／rosters 整檔後來有其他票改動，ZIP 保存精確 diff。九區 grid rows 不變，不代表 props、門禁持久化、NPC 等整檔不變；rosters 第三章子表不變，不代表第二章從未更新。

CI [43114416692](https://github.com/deadline314/Nest-Egg/actions/runs/43114416692)，job130838550773，原 log SHA `cb4f2838c709130f035fb4eee958b02165ccba296b9e20bb906d3fd1fef0c162`：6個 process 的全部計畫列逐一解析，共88個唯一 group，**Chapter3EnemiesSuite 在 process4**，Chapter3Story 在0，AttackTokens 在1，Encounter 在4。整批 **98,797 / 0新失敗 / 0已知失敗 / wall660s**；Runalltests 與 DummyTexture 退出守門皆成功。原 log 沒有每套斷言數，`per_suite_assertion_counts=null`；沒有把總數分攤到第三章。較晚43151017874是skip，不計第二次實跑。

票內79、145、93,334／2、29,641、51,346、31,320與產生器通過的舊數字，未找到該票連結的原 log / command / exit，保持為歷史文字主張；本包不重建虛假的原始收據。最新 CI 與本輪補證另列。沒有原始 gameplay 負控制 raw 可追溯的舊說法不補造；本輪 standing 真中彈及新 reader 反例有自己的原件。

## 原三張圖的親看與範圍

全部是原0f就存在、到a4逐 byte 相同的 RGBA PNG，均 **1280×720**。本輪逐張看原尺寸，沒有縮放後冒充原圖。

| 原圖 | SHA256 | 看見與不能推論 |
|---|---|---|
| NE-272-pump-telegraph.png | f0d67741c5730af140d2e29fff9cafed3eadb36174e42fdb68f2cee54555c96a | 地面箭頭／終止線及低矮暫代 pump；右側可見吊軌機。單張不證明 .7s 或玩家已跳過。 |
| NE-272-insulation-lock.png | de84001dc797b9c77fbfb2c2ec6d36c632c67cd903b3ff0e5d95c40d0cbaa8a4 | 探頭與胸高水平亮線；同場地面 ram 箭頭。不能當盾擋或跳躍回放。 |
| NE-272-mezzanine-fight.png | 7873c0ec6da61ae2ad476b99731d83a99ed3bb84399f1945b457d2e7da500f2d | 下層近戰＋吊軌遠距，上方步道仍在；不是完整自然繞道。 |

原 producer `ch3_combat_scenario` 明示跳過劇情、初始移位、HP9999，等待正式 FSM 到預兆後停住角色拍照。這三張不是完整自然戰鬥、無法證明真人難度或獨占 GPU 效能；軟體 Vulkan 是原票記述，本輪沒有當年 backend 原 log 可以再確認。畫面仍是歷史版面，不冒稱目前所有 props／光影外觀完全相同。

## 新四臂、原紅與取樣前置

正常載入專用 D8c project 的 autoload，正式 `LevelData` + 原 cover_map；只在開始安排 player(704,320)與原 insulation(640,240)，之後不寫位置／速度／生命／狀態。新遊戲正常血量6、盾量100；沒有加裝特製盾。玩家局部使用既有 `AimInput.set_virtual_gamepad` 安排合成向左瞄準，真正 InputEventAction → parse/flush；不是實體手把。鎖定瞬間分別保持站立、按蹲、按盾、按跳。原 Enemy、ProjectilePool、Projectile、Hurtbox、Player 正常跑自然 physics/process，沒有手動呼叫更新。

| 最終四臂 | 原引擎斷言 | 原結果 |
|---|---:|---|
| standing-v4 | 8/0 | 真 pulse hit_received 一次，HP6→5，盾100不變 |
| crouch-v4 | 9/0 | HP6，原 pulse 從661.833穿到1069.167，經玩家柱時在蹲姿框上方 |
| shield-v4 | 9/0 | HP6，hit_blocked 一次，盾100→76；不是只看沒扣血 |
| jump-v4 | 9/0 | HP6，原 pulse 穿過玩家水平柱時在真跳躍框下方 |

四程序各獨立 user 環境，均真正 exit0、0腳本／引擎／退出診斷；完整參照來源與C364前後字典均相同，probe來源同一份。這是自然時鐘的無頭 fixture，不是自然整章或新 Forward+ 截圖。

所有失敗保留：standing-v1 原8項中4紅，因新工具漏了正式 smoke 的無頭前置；standing-culling-on-v2 同紅並保持420步 idle、位置(640,240)、無pulse。`is_physics_processing()` 原觀測是true，不能誤寫成false或有效process_mode。只使用既有 smoke 的 `Enemy.activation_culling_enabled=false` 後才自然發射，沒有強迫FSM或手動推物理。此旗標是 fixture RAM前置、程序內還原，不是產品修改。

v3 四臂已有35/0功能結果，但 wrapper 廣域前後SHA集合漏了兩份 art/vfx JSON（其原快照已核published）；reader真擋住，故不拿v3稱51份全前後守門。v4只修 wrapper 將全部 matched 路徑納入並保存C實際字典，重跑四臂；v3原結果不改。

## Metadata 勘誤與可攜驗證

初版查找的57／擴展68是 requested paths，包含 Git 預設引號化的兩個中文路徑與兩個不存在的猜測 helper 路徑，不能說是57／68份實體來源。原中間 index 封為 `replay/evidence-index-before-unquoted-path-fix.json`；最後改 `git diff-tree -z` 取真正路徑，移除錯查，逐讀得66個 published 實體。原 source物件、CI、PNG與引擎結果沒有改寫。早期函式比較曾連下一函式前註解也算進去，最後改依GDScript縮排擷取真正函式；原程式未改。

reader 製作時也曾錯讀 GitHub CLI run metadata 欄名為id而非databaseId、以及發現前述art未納SHA造成KeyError；那些是工具製作錯誤，不是產品紅。當時輸出只在工具終端，沒有冒造原檔log；v4與最終 reader另封。

**容器保存錯誤**：早期 mutable `delivery/raw.zip`（2,779,758B，SHA `f44568d16b6de1c57f1b5724b1ab8b98bc98c518dbac322891a2b94d97091d0f`，727虛擬檔／182ZIP成員）被同一工作路徑的v4封包覆寫；該早期容器 bytes 沒有保存，不能再報它仍存在、也沒有重建冒充原ZIP。其舊SHA只列在 `replay/early-container-index-only.json` 作勘誤。各原引擎 run/source/exit、CI及PNG原件仍完整保存，最後新epoch重新封入；這不改寫任何原引擎結果。中途第二個 mutable 容器6a8030dd…尚在原工作路徑，但也不是本次最終epoch。只有 final-v4 的凍結清單可供交付，後續不得在同一epoch重產。

`raw.zip` 是去重儲存的**原始 bytes**，`members.json` 將原虛擬路徑對到 `objects/<SHA256>`。沒有正規化換行，原失敗也不覆寫。只去重儲存，不省略成員。`evidence-index.json` 給各 Git 版本／圖／6分片與地圖清單；`raw-index.json` 給實際ZIP大小與整包SHA。

```powershell
python verify.py --root <本資料夾>
python negative_controls.py --root <本資料夾>
```

reader 使用 Python＋Pillow，離線驗 CRC／所有物件與引用 SHA、66來源、原圖尺寸、6分片88組／總數、九區實際生成格、四臂原收據、自然時鐘與實際 pulse 軌跡／盾回呼。`reader-negatives.json` 是把已驗原 bytes **解碼後在記憶體**分別移除 crouch 真flight、移除盾回呼、把 jump框改站地的反例；原35項ok旗標不變仍須拒絕。這三個是reader反例，沒有冒充另外三輪遊戲負控制。
