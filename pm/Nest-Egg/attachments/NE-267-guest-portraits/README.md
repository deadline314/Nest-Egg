# 第二章三位客人頭像

原鄭先生、陳女士與洪先生共用同一個男性居民替身。現在各有成年人的獨立面孔：鄭58、陳44、洪35，沿用原講者id、姓名、故事選擇、旗標與交易。這個交付單位只做頭像；整票九位配角的完整分件與指定動作沒有冒稱完成。

## 來源與可重建性

先讀User-guide、WORLD及S18–S20的原劇本，再比較[五款同類遊戲的實際圖片](../../../../design/08-lighting/READABILITY_REFERENCES.md)與既有老K／護理師畫風。只借辨識清楚的輪廓和低彩度衣物，不推定他作流程或玩家普遍偏好。

[頭像來源配方](../../../../art_src/characters/ch2_guest_portraits/README.md)：三個實際1024×1536 RGBA原圖保留在各角色01_design，含原prompt、provider artifact、SHA、alpha直方圖；seed/model-job未提供記null，沒有假稱本機Comfy/Qwen/SAM。原生crop[340,0,660,320]，320×320，不放大、不重畫RGB；同既有流程alpha<40清除。原圖全身只是這次頭像的保留參照，沒有base_rgba或runtime character rig，不能當成已通過完整身體／分件驗收。

三來源先完整驗證才發布；重建`--check`逐byte相同，錯來源SHA負控制在任何頭像覆寫前失敗，三張既有輸出保持。黑／灰／白九個實際合成底都看過，與實際對話框的縮小顯示分開驗。

## 遊戲內證據

鄭、陳的正式對話與洪的錯誤重選分支，以真正Story載入的steps拍攝；構圖問題0、flags_unchanged=true，原生log無ERROR。這是直接播放該正式分支的畫面，不是人工全章通關；H10客人流程另走真正NPC／選擇，failures0且不重複付款。

全測合併候選固定base e63a6710、原選擇器75組，checks: 92874, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 637 s)；70輸入SHA前後相同，含已分票交付的NE-218／BG-46。分票rebase後核對生產來源與合併候選，必要專項結果另記。全測刻意壞資料ERROR與退出資源訊息原樣留存，不宣稱全log零ERROR。

來源改動只有三講者portrait路徑；整份故事還原這三路徑後與原故事相同。最新BG-46舞台、坐深0.50、問題返回和所有旗標由其正式來源保留。沒有為新增頭像註冊假骨架，也沒有引入找不到角色的替身警告。軟體Forward+的實際縮圖不取代其他配角與完整動作驗收。

## 重跑

`python art_src/characters/ch2_guest_portraits/build.py --check`；正常editor import；`python tools/story/build_ch2_story.py`。`GODOT=<4.7.2> SHARDS=4 tools/run_tests_changed.sh e63a6710`；正式畫面 `res://tools/stage_actor_capture.tscn -- --scene=ch2_t_s18_wrong --scene=ch2_t_s19_wrong_death --scene=ch2_t_s20_wrong_fine --out=<dir>`；H10安排條件的流程 `res://tools/ch2_flow_probe.tscn -- --guest-book-only --out=<dir>`。

[raw.zip](raw.zip)／[逐檔SHA](manifest.json)。原頭像替身畫面、錯來源負控制、九合成底、prompt、原生與全測log保留。

[分票來源核對、漏匯入的失敗與補匯入後重測](integration.md)。
