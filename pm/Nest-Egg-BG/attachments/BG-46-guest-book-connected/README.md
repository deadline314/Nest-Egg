# 客人簿舞台連接與坐位校準

讀User-guide後，先比較[五款同類遊戲的實際圖片](../../../../design/08-lighting/READABILITY_REFERENCES.md)與既有[舞台尺寸依據](../../../../design/10-presentation/STAGING_REFERENCE.md)。這些是視覺／家具比例比較，沒有據此宣稱其他作品的骨架或玩家普遍偏好。

## 正式行為

18段S17–S21正式來源接到客人簿房間；開始／收簿站在左側，陪客人時坐左椅，入口與已完成回訪仍在凜所在的館外。每個客人問題都有明確返回；選錯能重選、返回能再接續，完成過的不重複付款。舞台id `ch2_guest_book_room` 不變。

原圖的地上坐墊和椅坐姿不相容，改成成人椅與茶桌的新構圖。實際來源1843×853，runtime逐byte相同、沒有放大；圖並非保留中央像素的延展。三次生成的原圖、精確prompt、實際尺寸和採用理由在[generation.json](generation.json)，seed／model job不可得記null；沒有冒稱本機Qwen或SAM結果。舊原圖與Commit-1的Arc B580照片保留。

## 家具與演員

- 背景位置(-140.75,-36)、scale0.5、source_width1843；地板y265.5。
- 左椅座面x204.25–272.25／y209；右椅x377.75–442.75／y209；茶桌頂面y180，rect[271.25,180,106,85.5]。原比例門檻不改。
- 阿梨scale3.9，腳底y265.5；站x150、坐x232；鏡頭(320,206.3)、zoom0.84。NE-218新坐姿去除舊褲圓蓋後需將坐深0.43校準到0.50，原站姿、骨長、地板和鏡頭保持；舊0.43浮空候選也在raw。
- 坐深是該演員的有限資料參數，未設定仍用原預設；壞值安全退回。腳的IK、坐站過渡與共享姿勢原資料不被更改。

## 證據與限制

[raw.zip](raw.zip)含頭尾與各客人實際舞台、原生H10客人入口的選擇流程、初次失敗與完整log。`--guest-book-only` 先安排可進入該段的劇情條件，再走真正NPC互動與選擇；不是從序章完整人工通關。`stage_actor_capture --scene`直接播放正式steps、保持故事旗標不變，只證明構圖，不冒稱完成任務。

- 正式客人流程：failures0、退出0、無ERROR；未先選正確答案不發錢，三位20/40/60、收簿100、回訪不再付款，返回後暫停釋放。
- 四張最後校準畫面：過場／構圖問題0、flags_unchanged=true，腳沒有被對話框蓋住，頭在上黑邊之下。
- 合併候選原選擇器固定base e63a6710：75組；checks: 92874, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 637 s)。70個輸入SHA在執行前後相同。候選含NE-218姿勢及NE-267頭像，分票推送；圖片標示此合併候選，BG-46本身不把三訪客頭像算成自己新增的素材。正式分票還原與rebase後的必要專項另記整合紀錄。
- 原生均Godot4.7.2／llvmpipe軟體Forward+。自動檢查log包含刻意壞資料ERROR、退出資源訊息，沒有宣稱全輸出0ERROR；所有腳本錯誤一律保留並不接受。
- 初次新背景mipmap=true違反既有環境匯入政策；產線改為交付後套用同一政策，false後import與全測通過。原失敗不刪。

[素材重建配方](../../../../assets_src/pipeline/guest_book_seating.json)；`python tools/assets/stage_seating.py`，先核來源SHA再寫入並套原匯入政策；`python tools/story/build_ch2_story.py`由正式來源重建，非手改生成JSON。重跑測試 `GODOT=<4.7.2> SHARDS=4 tools/run_tests_changed.sh e63a6710`；原生流程 `res://tools/ch2_flow_probe.tscn -- --guest-book-only --out=<dir>`。對照完整[逐檔SHA](manifest.json)。

[分票整合與必要專項](integration.md)。
