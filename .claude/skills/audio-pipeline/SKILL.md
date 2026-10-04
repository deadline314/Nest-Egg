---
name: audio-pipeline
description: 把 CC0 音效與音樂換進 Nest Egg 的完整流程：找來源、下載並登記授權、挑檔案、加工成遊戲規格（響度、修剪、迴圈）、寫進音效庫與音樂清單、驗收。要新增或替換音效、槍聲、命中聲、腳步、環境音、背景音樂，或要找免費音訊素材時使用。
---

# 音訊素材流程

背景與資料格式見 `design/16-audio/DESIGN.md`，素材來源目錄與缺口見 `design/16-audio/SOURCES.md`；票是 `pm/Nest-Egg/` 的 NE-154～NE-162。這份是照著做就能動的操作手冊。

## 原則

- **只收 CC0**。授權不明、CC-BY、CC-NC 一律不放進專案。新增來源時先在頁面確認寫著 CC0（OpenGameArt 顯示 `License(s): CC0`、Kenney 全部 CC0）。
- 原始下載檔在 `assets_src/raw/audio/`（git-ignored，可重抓）；進版控的是加工後的 `audio/**`、`assets_src/audio/{manifest,pipeline,LICENSES}.json`、`data/audio/*.json`。
- **所有加工由清單驅動、可重跑**。不要手改 `audio/**` 裡的成品；改 `pipeline.json` 再重跑。音量微調（`volume_db`、`pitch`）寫在 `data/audio/sound_bank.json`，加工工具重跑時會保留。
- 角色不做台詞配音；人聲只收非語言的呼吸、痛呼，並先確認沒有詞。

## 流程

1. **找來源**：把素材包加進 `assets_src/audio/manifest.json`（`id`、`kind: sfx|music`、`author`、`license: CC0-1.0`、`page`、`download`、`dir`）。先看 `design/16-audio/SOURCES.md` 有沒有現成的。
2. **下載**：`python tools/audio/fetch_audio.py [--only ID ...] [--kind sfx|music]`。已下載的會略過，單項失敗只記錄。
3. **看特徵再挑**：`python tools/audio/inspect_audio.py <素材包 id> "<路徑或萬用字元>"`，看時長、第一聲的範圍、衰減時間、頻譜重心、起音數。槍聲素材常有長尾與連發，要指定 `start`／`end` 取第一發。
4. **寫加工清單** `assets_src/audio/pipeline.json`：
   - `sfx.<音效 id>`：`category`（gun、impact、explosion、foley、ui、voice、ambience，對應 `defaults`）、`variants`（每項 `pack`、`file`，可覆寫 `mode: shot|whole|loop`、`start`、`end`、`max_len`、`target_db`、`gain_db`、`rate`、`lowpass`、`highpass`、`fade_out_ms`）。多個變體會輪播。
   - `music.<曲目 id>`：`pack`、`file`，可加 `start`、`end`、`loop_blend_ms`、`fade_in_ms`、`fade_out_ms`、`target_lufs`。
5. **加工**：`python tools/audio/build_audio.py`。先用 `--check` 檢查來源檔都在、`--report` 看每個輸出的時長與響度、`--scratch <資料夾>` 試做（不動專案檔）。輸出音效單聲道 44.1 kHz、有聲部分 RMS 對齊 `target_db`、峰值不超過 -1 dBFS；音樂立體聲、整合響度對齊 -18 LUFS。同時更新 `data/audio/sound_bank.json` 的 `files`／`pack` 與 `assets_src/audio/LICENSES.json`。
6. **匯入**：`godot --headless --editor --quit` 產生 `.import`（要一起 commit）。
7. **驗收**：`GODOT=... tools/run_tests.sh`（AudioSuite 會檢查授權登記、未被引用的音訊檔、缺檔）；在音效實驗室（NE-162）試聽。

## 踩過的坑

- `assets_src/` 有 `.gdignore`，Godot 不匯入也不能用 `res://assets_src/...` 走 ResourceLoader；測試要讀這裡的檔用 `FileAccess`。
- 原始檔的音量差異很大（-4 到 -43 LUFS），一律經加工標準化，不要直接複製。
- Firearm Library 是 96 kHz／24 bit 立體聲、5–30 秒；自動找第一發的結果只是參考，用 `inspect_audio.py` 確認後手動指定 `start`／`end`。
- 缺檔測試用的 id 與路徑要含 `test_audio_`，`tools/run_tests.sh` 才會忽略它們的預期錯誤。
