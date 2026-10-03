# tangle_wire（纏絲）立繪

票：NE-92。第二章，藏在牆內的觸手簇。只畫牆洞口（本體）與單條觸手。深灰牆板加暗紅黑色電纜觸手，電火花是黃白色。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體（牆洞口） | `body_s2.png` | 2 | 832x832 | 正面看的圓形破牆板：外緣是鋸齒狀撕裂的深灰鋼板，洞緣是翻捲的鋼板、折斷的導管與破電纜（幾點黃白火花），洞心是深黑的空洞；沒有觸手 |
| 單條觸手 | `tentacle_s1.png` | 1 | 512x1216 | 垂直伸直、尖端朝下的細長電纜狀觸手，暗紅黑橡膠外皮與幾條外露銅線，右側一排小圓黃白吸盤，尖端黃白火花；根部是圓球 |

不採用的候選：`body_s1.png`（seed 1，整張畫面被牆面填滿，alpha 99%，無透明邊界）。

## 重畫紀錄

- 本體重畫 1 次。seed 1 把整個畫面畫成滿版牆面（要求「只要牆洞」但沒有切成獨立物件）；seed 2 改成「單獨一塊圓形破牆板、周圍是空的透明背景」後合格。
- 觸手 0 次。

## 提示詞（英文原文）

body（最終，seed 2）：
> A single round patch of torn steel wall plating with a hole in its center, cut out as an isolated object: a roughly circular ragged-edged chunk of dark gunmetal wall plating with a jagged torn outer border, seen straight-on from the front. In the middle of the chunk is an irregular oval hole whose rim is bent, peeling steel with snapped conduit pipes, frayed black cable ends, bolts, and tiny yellow-white electric sparks. The inside of the hole is a deep dark empty void with faint maroon shadows. Dark gunmetal and maroon colors. The chunk is surrounded by empty transparent space on all sides, with margin around it, centered in the picture. Nothing else in the picture: no tentacles, no ground, no shadow, no text, no other objects.

tentacle：
> A single straight vertical slender tentacle that looks like a living electrical cable, with its thicker round root at the top and its tip pointing straight down: it tapers smoothly from medium thickness at the top to a very thin needle tip at the bottom. Dark maroon-black rubbery sheath with fine ribbing and a few exposed copper wire strands, a single row of small round bright pale-yellow suction nodes along its right side only, and a tiny bright yellow-white electric spark glowing at the very tip. Perfectly straight and vertical, clean edges, placed in the exact center of the picture. Only one tentacle, not curved, not coiled. Nothing else in the picture: no body, no wall, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 牆洞口是「正面」視角（牆面朝向觀看者），不是側面，因為牆洞本來就是貼在背景牆上的東西。洞心不是透明的，是不透明的深黑，觸手從洞心中央長出來；拼合示意（`pm/Nest-Egg/images/NE-92-assembly.png`）用 6 條、縮放 0.42 到 0.66 倍、朝四面放射。
- 觸手很細（尖端近乎針尖），與打撈臂（粗短、深藍綠、有大吸盤）一眼可分；線條有細微起伏但最粗處只約畫面寬的四分之一，做網格變形時網格寬度請依實際粗細設定。
- 觸手根部是一個圓球頭，洞心的深黑可以蓋住它。
- 牆洞口的鋸齒外緣不是雜點，是設計。
