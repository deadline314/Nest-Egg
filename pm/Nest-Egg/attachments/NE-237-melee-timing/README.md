# NE-237 預設 MeleeSuite 三項間歇失敗的時序定位

基準 ebb4c65356605e335bac6cdf143ef90dd5032483，分支 codex/cloud-melee-regression。主 session 在本機 06c440760 UI worktree 的原 changed selector 單 worker 60 groups 中報三項近戰失敗；原本機 raw 位於 C:/tmp/contextual-ui-checks/changed-tests-retry/shard_0.log，雲端不可直接讀，這份不冒稱檢視本機檔案。後續本機 UiScreensSuite＋MeleeSuite 單 worker 未重現近戰失敗，與雲端一般速度原套件通過一致。

## 確切復現

Fresh import class cache 完成（exit0、無 SCRIPT ERROR），才執行原來未修改的 MeleeSuite：原 run_tests_parallel.sh、SHARDS=1，25 checks，0 new/known failures、exit0，9秒。

同一未改來源，以 Godot --headless --max-fps 30 res://tests/smoke_test.tscn -- --only=MeleeSuite 執行（獨立 XDG_DATA_HOME），25 checks、3 failures、exit1、0 SCRIPT ERROR，精確為：

    the buffered press chains into the second swing
    a hit cancels the recovery early (41 frames of 9)
    the third swing of the combo is the heavy slash

--max-fps 為可重現的 process/render 上限，不改60Hz physics tick、產品時序／傷害，也不是實測遊戲FPS或硬體性能。這個復現單獨足以觸發三敗，不需要假設 UI 改了攻擊資料或套件污染。

僅新增只讀 trace 後，同條件再次精確三敗。輸入 wall_ms6437、期限6657；第一招進 recovery 時 wall_ms6628、剩餘29ms，取消成本50ms。第一刀真HP999→997、方向[-1,0]、facing -1、目标相距19.16，仍在26範圍。命令先過期，第二段未啟動；等 combo_window 也過期，index -1，測到41影格。後續呼叫開始新的第一刀（HP995/index0），第三重斬斷言因而連帶失敗。沒有單憑最終 failure 字串推定產品 bug。

預設頭招 windup50ms＋active60ms＋cancel_after50ms，約160ms物理進度，再加局部hitstop50ms，距220ms即時命令只剩約10ms餘裕。render量化／慢機處理可耗尽餘裕；期限不因 hitstop 延長，正是既有授權設計。source-comparison 顯示本套件、Player、command input、預設近戰／輸入資料、AimInput、Fx 與06c440760全部逐位元組相同。

## 窄修復與保留的強度

唯一遊戲測試 source 變更為 tests/suite/test_melee.gd，另補設計。没有修改任何產品 source、shared Fx、角色／動畫核心、Main／Level／Story／RunSnapshot、保存或升級服務。runner／selector／known_failures 完全保持。

三個原斷言的條件與上限原樣保留：第二招 index1；早取消 ≤ int(recovery×60)-3（本資料為6影格）；第三招 index2 且等於 heavy 的既有傷害。起手、揮空完整收招、單目標一次、衝刺鎖、尾跡生命與窗口重置的原測試仍執行。新增 fixture方向斷言及取消前不可取消斷言，沒有放寬角度／range／frame threshold。

有效案例在第一招 recovery初期重新點按，仍先付50ms取消成本；第二招 recovery中再點按第三招，第二招若揮空仍吃原完整收招。没有重試／連續刷新同一命令，沒有直接tick、手動thaw或改clock。

到期案例使用真現有液壓槌：340ms windup 本來就長於220ms buffer。起手同格第二按入真命令，物理整招自然完成、真命中扣6HP、觀察真正局部hitstop，驗期限未延長、未自動接第二招。首次新增負案例錯用快速頭招：一般速度下可合法於期限內接續，因此該輪34checks/3fail/exit1與來源原樣保留，修正 fixture 後才列成功。不拿一個有時有效的輸入當必定過期的證據。

## 實跑結果與來源

原始、診斷、失敗、修後 raw／exit 與純文字 source 快照均保存；SCRIPT ERROR 判定不被 known failures 豁免。可選 --melee-evidence-out 僅在真正Forward+中保存自然第三招影格，一般headless測試不擷取、不改鏡頭。圖不代表正式握持美術、真人手把或人工遊測。

最終結果由 results.json 及對應 raw 提供。source.diff 為窄來源差異；sha256.json 對應實際 source、raw和nativePNG。NE-237全票保持進行中；本次只交付既有測試的有效期限與取消回歸。


最新 main a5efd3e4 為NE-90離線mask工具與SOP／證據，沒有改runtime／素材；已rebase並驗11份戰鬥／動畫source逐位元組一致。聯跑與最終原生證據的來源分列於rebase-source.json。首張Forward+功能38checks通過，但章節卡遮住角色，保留title-obscured原圖／raw；只在可選擷取分支等卡片自然淡出4.2秒後重拍，不修改卡片、HUD、角色或動作。重拍同樣38checks/0fail/exit0、原生1280×720、zoom3.4、物理phase ACTIVE/index2/pose_t0.4；此圖不代稱持槍中的預設近戰動作／握持美術已驗收。

rebase後首輪changed的runner紀錄36checks/0fail/exit0、0SCRIPT ERROR，但工具最外層completion回1，兩者不一致，原樣保留且不列最後合格結果；最後完整source另跑原changed selector，結果另存latest-final-*。刻意bad-data ERROR、既有退出清理／物理診斷不刪除，不宣稱全raw無ERROR。
