# buoy_worm（浮標蟲）立繪

票：NE-92。第一章淹水通道，水面爬行的蟲。橄欖綠外殼加萊姆綠浮標燈（章內沒有其他綠色敵人，不撞色）。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體 | `body_s4.png` | 4（由 s2 編輯） | 1248x832 | 圓胖分節的毛蟲型身體，橄欖綠重疊甲殼、深褐腹部，前方（右）鈍頭與兩顆小黑眼，背上一根短柱托著萊姆綠發光浮標燈（紅白條紋環）；底緣一排空的腿座，**剛好 6 個**（等距，從尾到頭）；沒有腿 |
| 單條腿 | `leg_s1.png` | 1 | 832x832 | 單條短粗腿，垂直朝下：圓髖關節、粗上段、小膝、較細下段、圓鈍小腳掌；六對腿用同一張複製 |

重畫次數：本體 3 次（s2、s3、s4），腿 0 次。不採用的舊圖與候選：`body_s1.png`（只有 5 個腿座）、`body_s2.png`（7 個腿座）、`body_s3.png`（7 個孔在身側而不是腹下）。

## 提示詞（英文原文）

body：
> A chubby mechanical-organic worm creature that crawls on water, seen from the side: a fat plump segmented caterpillar-like body with overlapping olive-green armored shell plates, dark brown underbelly, a small blunt head at the front (right side) with two small round black eyes and a tiny mouth. On top of its back stands a short stalk carrying a round buoy lamp with a bright glowing lime-green bulb and a striped red-white ring collar. Along the underside are six small round empty leg sockets (the legs are NOT drawn). No legs, no water, no splash. Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

leg：
> A single short stubby leg of a chubby crawling worm creature, hanging straight down: a round hip joint at the top, a thick short upper segment, a small knee joint, a short lower segment, and a small rounded clawed foot at the bottom. Olive-green armored shell plates with dark brown joints, matching a plump caterpillar creature. Only one leg, perfectly vertical and centered in the picture, flat side view, drawn at about one third of the picture height. Nothing else in the picture: no body, no water, no ground, no shadow, no text, no other objects.

## 重畫紀錄（2026-10-04，補上第 6 個腿座）

- 原本只有 5 個腿座。seed 2、seed 3 都改成「剛好 6 個」的提示詞，Qwen 數不準，兩次都畫成 7 個（s3 的孔還跑到身側）。第 3 次改用編輯模式：以 s2 當參考圖，要求「移除尾端最左邊那個，剩下剛好 6 個，其他全部不動」，一次得到 6 個，身體、浮標燈與輪廓和 s2 完全相同，採用（s4）。
- 2026-10-04 全部立繪清過背景：Qwen 在「透明背景」上會留一層極淡的紫色薄霧（alpha 1～8），已清成全透明（`creature_art.py` 之後生成的圖會自動清；舊圖用 `--clean` 補清）。

編輯的提示詞（seed 4；參考圖 `body_s2.png`；前面加 `This is an RGBA image with transparency.`，後面加 `The image has alpha channel and the background is transparent.`）：
> Remove the leftmost small round socket under the tail end of the worm, so that exactly six small round sockets remain along the belly from the tail to the head. Keep everything else exactly unchanged: the worm, its shell plates, its colors, the buoy lamp, the head, the outline, the art style, the size and the position. Strict side view facing right.

## 取捨與注意

- 本體有 6 個腿座，腿座中心約在 x = 287、416、537、670、792、922、y = 545（圖座標，1248x832）；腿圖的髖關節圓球約在 (407, 190)；新拼合示意 `pm/Nest-Egg/images/NE-92-assembly-v2.png` 用 6 條腿、縮放 0.36 倍。
- 腿的顏色（黃綠）比本體（暗橄欖綠）略亮，需要的話遊戲裡把腿調暗一點。
- 腿的「爪」並不明顯，是圓鈍的腳掌，符合「短腿」設定。
- 本體底緣沒有水線，水面效果之後用特效或裁剪。
