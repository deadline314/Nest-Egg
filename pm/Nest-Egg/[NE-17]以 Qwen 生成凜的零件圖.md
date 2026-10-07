# [NE-17] 以 Qwen 生成凜的零件圖

> 狀態：審查中

## 內文

### 需求
凜的零件圖目前是程式畫的暫代圖。改用 Qwen Image 2.1 Uncensored 依 A 畫風（動漫賽璐璐、Edgerunners 風）生成全身立繪，再自動切成零件圖覆蓋現有的圖。尺寸與支點不變，不改程式。設計見 `design/03-art-pipeline/ART_PIPELINE.md` 第 5 節「本機環境」與「做法 C」。

### 來源
2026-10-03，使用者換到 RTX 4070 SUPER 的機器，要求用 Qwen Image 2.1 Uncensored 先畫女主角、切成分件圖放進 Godot 試試看，並提出「看起來太稜角、可否放高清圖進去」「每一次的產出都給我看截圖，過程也可以，寫在票裡面」。更早之前：「照 ART_PIPELINE.md 的規格，用 ComfyUI 畫出同尺寸、同支點的零件 PNG，覆蓋掉現在的圖就好，程式不用改」「先處理女主角」「有辦法直接根據生出來的立繪生成部件圖嗎?」「改用 Qwen 繼續做凜的零件圖」。畫風由使用者從 4 種候選中選定 A。

### 驗收條件
- [x] 過程中每一次產出（文生圖、立繪、切出的零件、預覽、遊戲內畫面）都附截圖在本票「進度紀錄」，使用者隨時能看到進度
- [x] 凜改為約 7.5 頭身、成熟有曲線的造型（高衩連身衣、過膝絲襪、厚底靴，保留白色高馬尾、粉紅髮尾、青色眼睛與金屬義手），以使用者選定的 s33 為定稿
- [x] 凜使用專屬的 7.5 頭身骨架，待機、跑、跳、瞄準、蹲、格擋、受傷、倒下都沒有錯位或縫隙，持槍位置正確
- [x] 凜的零件圖全部由定稿立繪切出，邊緣平滑、沒有多邊形稜角，臉部細節清楚
- [x] 受傷時衣物依生命比例逐片被打飛（外套、絲襪、連身衣），露出破損的底層，且關鍵部位仍有碎布遮住
- [x] 遊戲內凜整體放大 1.15 倍（原訂約 1.4 倍，NE-71 因頭探出碰撞框過多改為 1.15），碰撞範圍維持不變，關卡可正常通過
- [x] 立繪與零件使用 4070 SUPER 上的 CUDA ComfyUI 生成，高解析度立繪不超過 6 分鐘一張
- [x] 有發光部位的零件附上新的 `*_glow.png`，霓虹位置與新圖一致
- [x] 外觀符合設定：白色高馬尾髮尾粉紅、青色眼睛、深藍長外套配洋紅內襯與青色飾線、緊身連身衣（顏色以使用者選定的 s33 為準：白色）、白色裝甲片、金屬義手、靴底粉紅發光
- [x] 七種動作（待機、跑、瞄準、蹲、跳、格擋、死亡）沒有錯位、縫隙或穿幫
- [x] 受傷脫甲後，裝甲底下的身體是完整的
- [x] 現有 s33 定稿附預覽並取得使用者同意沿用；本次同意不追認歷史覆蓋前批准
- [x] 凜出現的遊戲畫面（關卡、背包、過場）顯示正常，沒有錯誤訊息

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
2. 預覽工具與第一關截圖確認正常（不跑完整測試套件）。
3. 截圖存到 `pm/Nest-Egg/images/NE-17-*.png`。
4. 在這張票加 Commit 段落、狀態改「完成」、驗收條件打勾。
5. Commit。訊息不要出現 Claude 等 AI 字樣，也不要加 Co-Authored-By。

### 測試流程
1. 執行 `tools/rig_preview.tscn`，檢查凜的七種動作沒有錯位或縫隙
2. 進入第一關，跑、跳、瞄準、格擋，確認新外觀與發光層正常
3. 受傷數次，確認裝甲逐片脫落，底下身體完整
4. 開背包與第一關，確認凜的畫面正常

---

# 進度紀錄

> 每次產出都附截圖，由舊到新。

## 1. 文生圖與「直接出分件圖」實驗（4070 SUPER，約 55–61 秒一張）

單張全身立繪的外觀符合設定。另外試了用 prompt 一次輸出立繪加分件圖，概念圖漂亮，但零件視角混雜、沒有統一支點，不能直接綁骨架。

![文生圖：全身立繪](images/NE-17-step1-text2img.png)

![實驗：立繪加分件圖](images/NE-17-step1-direct-sheet.png)

## 2. 依骨架姿勢生成立繪（約 5 分鐘一張，1280×1856）

![立繪：身體](images/NE-17-step2-illustration-body.png)

![立繪：含裝甲](images/NE-17-step2-illustration-armor.png)

## 3. 切出的零件

第一版沿用舊零件的多邊形輪廓、解析度與原本相同，邊緣稜角明顯。第二版改取立繪本身的外緣、解析度 2 倍。

![零件第一版](images/NE-17-step3-parts-v1.png)

![零件第二版（2 倍解析度）](images/NE-17-step3-parts-v2.png)

## 4. 預覽工具

![第一版：八種動作](images/NE-17-step4-poses-v1.png)

![第二版：八種動作](images/NE-17-step4-poses-v2.png)

![第二版：頭部放大](images/NE-17-step4-head-v2.png)

![第二版：特寫](images/NE-17-step4-closeup-v2.png)

## 5. 遊戲內（Q 版第二版）

![第一關（霓虹市集）](images/NE-17-step5-ingame-market.png)

## 6. 7.5 頭身新造型（使用者要求參考「修長比例、有曲線」的樣式）

約 4 頭身的 Q 版骨架畫不出那種比例，因此先出新造型，再依造型重做骨架。三個種子，使用者選定 s33。

![造型 s31](images/NE-17-step6-design-a-s31.png)

![造型 s32](images/NE-17-step6-design-a-s32.png)

![造型 s33（定稿）](images/NE-17-step6-design-a-s33.png)

## 7. 依定稿切件

在立繪上標出關節（頭、肩、肘、腕、髖、膝、踝、馬尾），每個像素歸給距離最近的骨頭，肢體轉正後裁成零件；被手臂遮住的軀幹與骨盆自動補畫，骨架長度也從立繪量出。

![像素歸屬](images/NE-17-step7-ownership.png)

![切出的零件](images/NE-17-step7-parts-tall.png)

## 8. 預覽工具（7.5 頭身骨架）

![八種動作](images/NE-17-step8-poses-tall.png)

![特寫](images/NE-17-step8-closeup-tall.png)

![頭部放大](images/NE-17-step8-head-tall.png)

## 9. 遊戲內

![第一關（霓虹市集）](images/NE-17-step9-ingame-market-tall.png)

## 10. 改用 SAM 3.1 摳圖

先前用「離骨頭最近」猜每個像素屬於哪個零件，馬尾、外套、遠側的腿都會混在一起。改用 SAM 3.1（ComfyUI 內建節點）以文字提示摳出頭髮、馬尾、外套、金屬義肢、連身衣、絲襪腿、靴子、槍套等語意遮罩，每一類只能分給對應的零件。

![SAM 3.1 的十個文字提示遮罩](images/NE-17-step10-sam-masks.png)

![像素歸屬（SAM 引導）](images/NE-17-step10-ownership-sam.png)

![切出的零件](images/NE-17-step10-parts-sam.png)

## 11. 補強接縫後的結果

![零件](images/NE-17-step11-parts-sam2.png)

![特寫](images/NE-17-step11-closeup-sam2.png)

![八種動作](images/NE-17-step11-poses-sam2.png)

![頭部放大](images/NE-17-step11-head-sam2.png)

## 12. 破衣效果

受傷時衣物逐片被打飛，沿用裝甲脫落機制。底層是「破損版」立繪（Qwen 依原圖改成衣物撕裂，姿勢與比例完全保持，對位誤差不到 1px）；上層是完整版切成的六組衣物片（袖子、外套、絲襪大腿、絲襪小腿、連身衣下半、連身衣胸口），依序脫落。露出程度停在破損但關鍵部位仍有碎布遮住。

![破損候選：原圖與三個種子](images/NE-17-step12-damaged-candidates.png)

![生命 100% 到 0%（s41，較保守）](images/NE-17-step12-damage-stages.png)

![生命 100% 到 0%（s42，破損較多）](images/NE-17-step12-damage-stages-s42.png)

![破損底層的八種動作](images/NE-17-step12-poses-s42.png)

## 13. 絲襪最後才脫落

脫落順序調整為外套 → 連身衣 → 絲襪，底層改用破損最多的版本（s43）。絲襪即使在最後階段仍留有破損的殘片。

![生命 100% 到 0%（絲襪最後脫落）](images/NE-17-step13-damage-stages-stockings-last.png)

## 14. 修正衣物片涵蓋不全

血量 100% 時腰部、臀部露出底層皮膚，和原圖對不上：衣物片只切了 SAM 認得的連身衣、絲襪、外套，黑色腰帶這類沒歸類的衣服，以及瞄準時被手臂遮住後補出來的那一塊，都沒有被蓋住。修正後衣物片涵蓋該零件上所有衣物，並向外擴一點，100% 血量與原圖一致。

![原圖與遊戲內 100% 血量對照](images/NE-17-step14-fidelity-compare.png)

![生命 100% 到 0%](images/NE-17-step14-damage-stages.png)

![八種動作](images/NE-17-step14-poses.png)

## 24. 新流程試做：設計稿 → 部件版面

先用目前的凜當參考，生成「正面 T-pose ＋ 側面」的角色設計稿（可當角色的初始設計稿）。

![設計稿候選（三個種子）](images/NE-17-step24-turnaround.png)

## 25. 側面 → 各部件版面

拿設計稿的側面圖，要求 Qwen 畫出「左邊整體側面、右邊各部件」，並註明每個零件要畫完整、被遮住的部分也畫出來、接合處多畫 15% 重疊。馬尾、臉、前髮、含臀部的身體、含槍套的大腿、含靴子的小腿、整條義肢都一次畫出。

![部件版面](images/NE-17-step25-parts-sheet-s81.png)

![取出的部件](images/NE-17-step25-parts-extracted-cc.png)

## 26. 部件版面（膝蓋不單獨畫關節）

![部件版面](images/NE-17-step26-parts-sheet-noknee.png)

## 27. 流程更新：直接生成透明背景的側面圖

取消「正面 T-pose 設計稿」。改成直接生成側面圖，並讓 Qwen Image 2.1 直接輸出透明背景（它原生輸出 RGBA，不需要去背模型）。提示詞格式依官方建議：開頭「This is an RGBA image with transparency.」，結尾「The image has alpha channel and the background is transparent.」，中間放角色描述；用 SaveImage 存 PNG 即保留 alpha。

![透明背景側面圖（黑、白、洋紅底）](images/NE-17-step27-rgba-side.png)

![邊緣放大（洋紅底）](images/NE-17-step27-rgba-edge-zoom.png)

SAM 對這張圖切出的遮罩幾乎沒有漏到背景（十個遮罩共 700 多個像素落在透明區，集中在髮絲）。

![SAM 遮罩](images/NE-17-step27-rgba-sam-masks.png)

## 28. 部件補全試做（身體）

用透明背景的側面圖，把「身體」（SAM 的軀幹加夾克遮罩）摳成殘缺部件，肩膀處有義肢遮住造成的缺口。把殘缺部件當第一張參考圖、完整角色當第二張，請 Qwen 補全被擋住的部分（84 秒一張，輸出同樣是透明背景）。

Qwen 把肩膀、上側軀幹、夾克補得很自然，但同時把頭髮、臀部、絲襪也重畫進來，沒遵守「不要畫」的指示。因此補全結果只取缺口範圍（義肢遮罩擴張後與部件外輪廓的交集），其餘維持原部件。

![補全前後](images/NE-17-step28-body-complete.png)

![只取缺口後](images/NE-17-step28-body-final.png)

## 29～34. 依透明背景側面圖分件、補全、放進 Godot

依使用者決定的新流程：透明背景側面圖 → SAM 3.1 分群 → 被擋住的群組請 Qwen 補全（只取缺口）→ 依關節切成零件，夾克與槍套獨立成配件 → 放進 Godot。完整流程、每一步的輸入輸出、零件位置與替換方式見 `design/03-art-pipeline/CHARACTER_PIPELINE.md`，一鍵腳本是 `tools/comfyui/build_character.py`。

補全結果（身體、手臂）：

![補全後的身體](images/NE-17-step29-group-body.png)

![補全後的手臂](images/NE-17-step30-group-arm-v2.png)

夾克與馬尾第一次補全時，Qwen 把頭、手臂又重畫進缺口。改成「剝層」：整張圖移除義肢與槍套得到階段 A，夾克的完整版取自階段 A。馬尾沒有需要補的地方，改用原圖摳出，避免階段圖邊緣的淡色光暈。

![剝層圖](images/NE-17-step31-stages.png)

![馬尾（原圖摳出）](images/NE-17-step34-hair-from-original.png)

![13 張零件圖](images/NE-17-step32-textures.png)

![原圖與遊戲內對照](images/NE-17-step34-final-closeup.png)

![八種動作](images/NE-17-step34-final-poses.png)

---

# 跟其他票的關係

- Blocks：NE-68、NE-69、NE-70、NE-71、NE-72
- Blocked by：無
- Related：NE-7

---

# Commit-1

## 內文

這張票的驗收項目是 NE-68～72 拆出去之前寫的，多數早已完成卻沒勾。現在對照現況逐條核對：
- 進度紀錄 34 步每次產出都附截圖；定稿是使用者選的 s33、專屬 7.5 頭身骨架；立繪約 5 分鐘一張。
- 零件由定稿切出；八種動作（待機、跑、瞄準、蹲、跳、格擋、硬直、倒下）預覽沒有錯位或縫隙；發光層（靴底、武器等 6 張）位置與新圖一致。
- 受傷時外套、絲襪依生命比例逐片脫落，底下的身體完整（NE-70 已完成）。
- 遊戲內放大倍率已由原訂 1.4 倍改成 1.15 倍（NE-71：1.4 倍時頭探出碰撞框 25 像素，子彈穿過頭部沒命中），所以驗收條件同步改成 1.15 倍；關卡通行與蹲下通道由 NE-71 驗證。
- 外觀依使用者選定的 s33：連身衣是白色（原條件寫黑色緊身衣，已改為以 s33 為準）。
- 凜出現的畫面：關卡與過場見 NE-71 的截圖，背包的角色狀態頁這次重新確認顯示正常。
唯一沒勾的是「覆蓋前先給使用者看預覽並取得同意」：票上沒有留下使用者對覆蓋當下預覽的明確同意紀錄，需要使用者確認後才能勾，所以狀態維持進行中。

### 測試結果

| 項目 | 結果 |
|---|---|
| 角色規格檢查與角色相關測試 | 同批受影響範圍測試 29967 項、0 新失敗 |
| 資料驗證 | 0 錯誤 |
| 執行 log | 無 ERROR |

### 截圖

![凜的七種動作（待機、跑、瞄準、蹲、跳、格擋、倒下）](images/NE-17-recheck-poses.png)

![受傷衣物脫落各階段（外套、絲襪逐片，身體完整）](images/NE-17-recheck-damage.png)

![背包角色狀態頁](images/NE-17-recheck-inventory.png)

---

# Commit-2

## 內文

2026-10-08 稽核既有定稿與來源；沿用現有凜，沒有重新生成或覆蓋素材。透明側面原圖與定稿 s33 的 SHA-256 相同：`401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9`。來源保存在 [原圖](../../art_src/characters/rin2/base_rgba.png)、[定稿](../../art_src/characters/rin2/01_design/design_s33.png)、[配方](../../tools/comfyui/recipes/rin.json) 與 [分割依據](../../tools/comfyui/specs/rin_side.json)；初次交付紀錄為 `501eece9`，目前角色定義最近的交付紀錄為 `9c572ecc`。

本次重新取得現有版本的 Forward+ 八動作及站姿特寫，供使用者確認沿用的外觀。歷史勾選沿用原交付紀錄，不代表本次重新驗收了全部動作；後續發現的接縫、外套與姿勢退化由 NE-222 處理。「覆蓋前先給使用者看預覽並取得同意」仍未勾選：原紀錄沒有覆蓋當下的批准，本次也沒有補造批准。

### 測試結果

| 項目 | 結果 |
|---|---|
| 原圖與 s33 雜湊比對 | 相同 |
| 角色分割規格檢查 | 0 錯誤、0 警告 |
| 零件與法線檢查 | 馬尾 1 處原有 541 px 空隙，其餘未報問題；空隙不當作本票修復成果 |
| 現有版本實際預覽 | Godot 4.7.2、Vulkan 1.4、Forward+、RTX 4070 SUPER；無 ERROR |
| 遊戲測試 | 本票只更新交付紀錄與預覽，未改遊戲，未執行 |

### 截圖

![現有凜的八動作：供確認沿用外觀，接縫由 NE-222 驗收](images/NE-17-session-current-poses.png)

![現有凜的站姿特寫（Forward+）](images/NE-17-session-current-closeup.png)

---

# Commit-3

## 內文

2026-10-08，使用者在看過 Commit-2 現有版本預覽後，明確回覆「同意沿用定稿並修復」。已記錄本次沿用 s33 的同意，接縫、分割與姿勢修復由 NE-222 持續驗收；本次同意不追認以前覆蓋前的批准。狀態維持審查中。

### 測試結果

| 項目 | 結果 |
|---|---|
| 使用者外觀確認 | 明確同意沿用定稿並修復 |
| 遊戲測試 | 僅更新同意紀錄，未改遊戲，未執行 |

### 截圖

![使用者同意沿用的現有 s33 外觀](images/NE-17-session-current-closeup.png)

---
