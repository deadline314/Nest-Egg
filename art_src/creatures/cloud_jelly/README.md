# cloud_jelly（雲母）立繪

票：NE-93。第三章，水母形懸浮機。半透明粉紫玻璃鐘罩加淡青色發光核心與青色電火花。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 鐘形本體 | `body_s2.png` | 2 | 832x832 | 圓頂玻璃鐘罩，**深飽和洋紫色**配深藍紫粗描邊、下半更深的陰影；底緣一圈亮青色發光環、白銀金屬邊與一圈暗洋紅荷葉邊裙（裙上有一排小圓座）；沒有觸鬚 |
| 單條觸鬚 | `tentacle_s2.png` | 2 | 512x1216 | 垂直伸直、尖端朝下，頂端圓球根、往下漸細到髮絲，深洋紫色玻璃外皮加深藍紫粗描邊，中心一排青色發光小珠，尖端一點青色電火花（與新鐘罩同色系） |

重畫次數：本體 1 次、觸鬚 1 次。不採用的舊圖：`body_s1.png`、`tentacle_s1.png`（淡粉紫霜面，亮背景上對比低）。

## 提示詞（英文原文）

body：
> The bell-shaped body of a floating jellyfish-like drone, seen from the side: a smooth round dome of translucent frosted glass in soft pink-lilac, with a brighter glowing pale-cyan core visible inside and faint radial ribs, ringed at the bottom edge by a thin white-silver metal rim with a frilled skirt of small round tentacle sockets. A few tiny glowing cyan dots on the dome. No tentacles are drawn (they are separate), no antennae. Strict side view, centered in the picture. Nothing else in the picture: no clouds, no ground, no shadow, no text, no other objects.

tentacle：
> A single straight vertical trailing tentacle filament of a floating jellyfish-like drone, with its thicker round root at the top and its fine tip pointing straight down: it tapers smoothly from medium-thin at the top to a hair-thin tip at the bottom. Translucent frosted soft pink-lilac skin with a darker lilac outline, a single row of tiny bright glowing pale-cyan beads running down its center line, and a small bright cyan electric spark at the very tip. Perfectly straight and vertical, clean edges, placed in the exact center of the picture. Only one tentacle, not curved, not coiled. Nothing else in the picture: no bell body, no clouds, no ground, no shadow, no text, no other objects.

## 重畫紀錄（2026-10-04，補強對比）

- 舊鐘罩是淡粉紫霜面，與淺色背景對比低。本體改成「深飽和洋紫、深藍紫粗描邊、下半更暗、底緣亮青色發光環」，seed 2 一次合格；觸鬚跟著改同色系（seed 2 一次合格），否則淡粉觸鬚接在洋紫鐘罩下會撞色。
- 2026-10-04 全部立繪清過背景：Qwen 在「透明背景」上會留一層極淡的紫色薄霧（alpha 1～8），已清成全透明（`creature_art.py` 之後生成的圖會自動清；舊圖用 `--clean` 補清）。

新版本體（seed 2）：
> The bell-shaped body of a floating jellyfish-like drone, seen from the side: a smooth round dome of deep saturated violet-magenta glass with a thick dark navy-violet outline and a darker shaded lower half so that the dome stays clearly readable on a bright background, a bright glowing cyan core visible inside and faint radial ribs, ringed at the bottom edge by a thin white-silver metal rim with a frilled skirt of small round tentacle sockets in darker magenta. A few tiny glowing cyan dots on the dome. No tentacles are drawn (they are separate), no antennae. Strict side view, centered in the picture. Nothing else in the picture: no clouds, no ground, no shadow, no text, no other objects.

新版觸鬚（seed 2）：
> A single straight vertical trailing tentacle filament of a floating jellyfish-like drone, with its thicker round root at the top and its fine tip pointing straight down: it tapers smoothly from medium-thin at the top to a hair-thin tip at the bottom. Deep saturated violet-magenta glassy skin with a thick dark navy-violet outline, a single row of tiny bright glowing cyan beads running down its center line, and a small bright cyan electric spark at the very tip. Perfectly straight and vertical, clean edges, placed in the exact center of the picture. Only one tentacle, not curved, not coiled. Nothing else in the picture: no bell body, no clouds, no ground, no shadow, no text, no other objects.

以下是舊版（seed 1，不採用）的提示詞：

## 取捨與注意

- 拼合示意見 `pm/Nest-Egg/images/NE-93-assembly.png`：7 條觸鬚以 0.5 到 0.7 倍、角度 -8 到 +8 度掛在裙緣，長度約為鐘罩寬的 1 倍，比例合理。
- 新版是深洋紫配亮青，與本章其他敵人（藍鱗雲蛇、金色蜂）一眼可分，在亮、暗背景上輪廓都清楚。觸鬚玻璃質是半透明（半透明像素約 33%）屬設計；尖端電火花是獨立的小連通區，不是雜點。新拼合示意見 `pm/Nest-Egg/images/NE-93-assembly-v2.png`（7 條觸鬚，縮放 0.55 倍、掛點約在裙緣 y = 640）。
- 觸鬚尖端的電火花是獨立的小連通區（約 720 像素），不是雜點；刪小碎塊時要保留。
- 本體底裙上的小圓座只是裝飾，掛點用裙緣位置。
