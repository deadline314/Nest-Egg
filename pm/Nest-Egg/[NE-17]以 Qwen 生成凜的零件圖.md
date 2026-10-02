# [NE-17] 以 Qwen 生成凜的零件圖

> 狀態：進行中

## 內文

### 需求
凜的零件圖目前是程式畫的暫代圖。改用 Qwen Image 2.1 Uncensored 依 A 畫風（動漫賽璐璐、Edgerunners 風）生成全身立繪，再自動切成零件圖覆蓋現有的圖。尺寸與支點不變，不改程式。設計見 `design/03-art-pipeline/ART_PIPELINE.md` 第 5 節「本機環境」與「做法 C」。

### 來源
2026-10-03，使用者於開發對話中提出：「照 ART_PIPELINE.md 的規格，用 ComfyUI 畫出同尺寸、同支點的零件 PNG，覆蓋掉現在的圖就好，程式不用改」「先處理女主角」「有辦法直接根據生出來的立繪生成部件圖嗎?」「改用 Qwen 繼續做凜的零件圖」。畫風由使用者從 4 種候選中選定 A。

### 驗收條件
- [ ] 凜的 18 張零件圖（含裝甲）全部換成 A 畫風的新圖，檔名、畫布尺寸、支點與原本完全相同
- [ ] 有發光部位的零件附上新的 `*_glow.png`，霓虹位置與新圖一致
- [ ] 外觀符合設定：白色高馬尾髮尾粉紅、青色眼睛、深藍長外套配洋紅內襯與青色飾線、黑色緊身衣、白色裝甲片、金屬義手、靴底粉紅發光
- [ ] 七種動作（待機、跑、瞄準、蹲、跳、格擋、死亡）沒有錯位、縫隙或穿幫
- [ ] 受傷脫甲後，裝甲底下的身體是完整的
- [ ] 覆蓋前先給使用者看預覽並取得同意
- [ ] 完整測試套件全部通過

### 執行步驟

**1. 啟動 ComfyUI**（約 30 秒；看到 `To see the GUI go to` 即完成）

```
cd C:\ComfyUI
./venv/Scripts/python main.py --listen 127.0.0.1 --port 8188 --bf16-unet --bf16-vae --bf16-text-enc --force-upcast-attention --reserve-vram 2.5 --disable-smart-memory
```

**2. 輸出參考姿勢**：產生 `body.png`、`armor.png` 與對應的 `.json`（零件轉換資料）。

```
godot --path . res://tools/comfyui/rig_reference.tscn -- --skin=rin --out=C:/ComfyUI/nest_egg/rin_ref
```

**3. 生成 A 畫風全身立繪**：在 `tools/comfyui/` 底下呼叫 `comfy_api.qwen()`，參考圖放步驟 2 的 `body.png`（先鋪上純淺灰底），解析度 832×1216。同一種子再生成一張 `armor.png` 版本。提示詞以下列內容為基底，並要求「維持參考圖的姿勢、比例與每個肢體的位置」：

> Anime cel-shaded character art in the style of Studio Trigger's Cyberpunk Edgerunners: flat colors, bold clean black outlines, hard-edged two-tone shading, saturated neon accents. Full body, side view, facing right. An adult woman mercenary, about 19 years old, slim athletic build. Long white hair in a high ponytail with hot-pink dyed tips, cyan glowing eyes, serious expression. Her right arm is a chrome military cybernetic prosthetic. She wears a dark navy techwear long coat (the coat itself is dark navy, only its inner lining is magenta) with thin cyan neon trim, a black bodysuit, white armor plates on the shoulder, chest and knees, and black combat boots with glowing pink soles. Plain flat light-grey background, no text.

- 參考：`C:/ComfyUI/nest_egg/out/qwen_rin_s11_0.png` 是已通過外觀確認的文生圖結果。
- 若編輯模式對不準姿勢，改用 Qwen 版 ControlNet（`ModelPatchLoader` 載入 `qwen_image_2.1_fun_controlnet_union_int8_convrot.safetensors`，搭配 `QwenImageDiffsynthControlnet`）。輸入是步驟 2 圖的線稿。
- 全身輪廓和參考圖疊起來誤差要在幾個像素內（可用半透明疊圖檢查），不然下一步切出來的零件會錯位。

**4. 切零件**（新增 `tools/comfyui/cut_parts.py`）：對 `.json` 裡每個零件：
1. 用轉換矩陣的反矩陣，把立繪取樣回零件畫布的 4 倍解析度。
2. 透明度直接沿用原本的暫代零件圖，所以輪廓、尺寸、支點都不變。
3. 依繪製順序算出哪些像素被前面的零件擋住（例如軀幹被前手擋住、頭被瀏海擋住），用 OpenCV `inpaint` 補畫。
4. 縮回規格尺寸（LANCZOS），透明度再套一次原圖。
5. 裝甲零件取自 armor 版立繪，其他零件取自 body 版。
6. 後側手腳共用前側的圖，不需要另外處理。

**5. 發光層**：從新零件挑出高亮度、高彩度的青色（色相約 170–200°）與洋紅色（約 300–340°）像素，其餘透明，存成同名 `*_glow.png`。只有規格表標示「有」發光層的零件需要。

**6. 預覽**：新圖先輸出到暫存資料夾（不要直接覆蓋 `art/characters/rin/parts/`），用預覽版截 `tools/rig_preview.tscn` 的七種動作。截圖寄給使用者確認。

**7. 覆蓋與驗收**：使用者同意後覆蓋 `art/characters/rin/parts/`。依序完成：
1. 開一次編輯器（或 `--headless --editor --quit`）重新匯入。
2. 跑完整測試 `GODOT=... tools/run_tests.sh`。
3. 截圖存到 `pm/Nest-Egg/images/NE-17-*.png`。
4. 在這張票加 Commit 段落、狀態改「完成」、驗收條件打勾。
5. Commit。訊息不要出現 Claude 等 AI 字樣，也不要加 Co-Authored-By。

### 測試流程
1. 執行 `tools/rig_preview.tscn`，檢查凜的七種動作沒有錯位或縫隙
2. 進入第一關，跑、跳、瞄準、格擋，確認新外觀與發光層正常
3. 受傷數次，確認裝甲逐片脫落，底下身體完整
4. 執行完整測試套件，全部通過

---

# 跟其他票的關係

- Blocks：無
- Blocked by：無
- Related：NE-7

---
