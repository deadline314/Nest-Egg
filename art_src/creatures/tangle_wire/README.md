# tangle_wire（纏絲）立繪

票：NE-92。第二章，藏在牆內的觸手簇。只畫牆洞口（本體）與單條觸手。深灰牆板加暗紅黑色電纜觸手，電火花是黃白色。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體（牆洞口，側面） | `body_s3.png` | 3 | 1216x832 | 嚴格側面朝右：一根粗短的深灰鋼導管從牆上扯斷，左端是切平的螺栓牆板法蘭（貼在牆面），右端是撕裂翻捲的洞口（翻起的鋼板瓣、折斷的管端、破電纜與幾點黃白火花），洞口內是深黑栗紅的空洞；沒有觸手 |
| 單條觸手 | `tentacle_s1.png` | 1 | 512x1216 | 垂直伸直、尖端朝下的細長電纜狀觸手，暗紅黑橡膠外皮與幾條外露銅線，右側一排小圓黃白吸盤，尖端黃白火花；根部是圓球 |

不採用的候選：`body_s1.png`（seed 1，整張畫面被牆面填滿，alpha 99%，無透明邊界）、`body_s2.png`（seed 2：合格但是「正面」視角的圓形破牆板，不是側面；已由側面版 s3 取代，保留供牆面貼圖用）。

## 重畫紀錄

- 本體重畫 1 次。seed 1 把整個畫面畫成滿版牆面（要求「只要牆洞」但沒有切成獨立物件）；seed 2 改成「單獨一塊圓形破牆板、周圍是空的透明背景」後合格。
- 2026-10-04 補強：原本牆洞口是正面視角（唯一不是側面的一張）。改畫成側面：把「牆內的觸手簇」畫成從牆上扯斷的導管，法蘭貼牆、洞口朝右，觸手從洞口伸出。重畫 1 次（seed 3）就合格。
- 觸手 0 次。
- 2026-10-04 全部立繪清過背景：Qwen 在「透明背景」上會留一層極淡的紫色薄霧（alpha 1～8），已清成全透明（`creature_art.py` 之後生成的圖會自動清；舊圖用 `--clean` 補清）。

## 提示詞（英文原文）

body（最終，seed 3，2026-10-04）：
> A short thick broken conduit stub of a cable nest that is torn out of a wall, drawn as a flat orthographic side elevation like a technical blueprint profile, absolutely not seen from the front: the camera sees the stub exactly from its side. It is an isolated object. A heavy dark gunmetal steel conduit pipe, about three times as long as it is tall, sticks out horizontally toward the right. At its left end it is cut off flat by a thin vertical bolted steel wall flange plate. At its right end is a ragged torn open mouth with bent peeling steel petals, snapped pipe ends, frayed black cable ends and tiny bright yellow-white electric sparks; the open mouth faces right and shows a deep dark maroon-black hollow. Dark gunmetal and maroon colors. Centered in the picture. Nothing else in the picture: no tentacles, no wall behind it, no ground, no shadow, no text, no other objects.

body（seed 2，正面版，不採用）：
> A single round patch of torn steel wall plating with a hole in its center, cut out as an isolated object: a roughly circular ragged-edged chunk of dark gunmetal wall plating with a jagged torn outer border, seen straight-on from the front. In the middle of the chunk is an irregular oval hole whose rim is bent, peeling steel with snapped conduit pipes, frayed black cable ends, bolts, and tiny yellow-white electric sparks. The inside of the hole is a deep dark empty void with faint maroon shadows. Dark gunmetal and maroon colors. The chunk is surrounded by empty transparent space on all sides, with margin around it, centered in the picture. Nothing else in the picture: no tentacles, no ground, no shadow, no text, no other objects.

tentacle：
> A single straight vertical slender tentacle that looks like a living electrical cable, with its thicker round root at the top and its tip pointing straight down: it tapers smoothly from medium thickness at the top to a very thin needle tip at the bottom. Dark maroon-black rubbery sheath with fine ribbing and a few exposed copper wire strands, a single row of small round bright pale-yellow suction nodes along its right side only, and a tiny bright yellow-white electric spark glowing at the very tip. Perfectly straight and vertical, clean edges, placed in the exact center of the picture. Only one tentacle, not curved, not coiled. Nothing else in the picture: no body, no wall, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 本體現在是嚴格側面（s3）：導管長度約是管徑的 3 倍，法蘭在左端貼牆，觸手從右端洞口（約 (1030, 430)）呼出，向右扇形展開；新拼合示意見 `pm/Nest-Egg/images/NE-92-assembly-v2.png`（5 條、縮放 0.5 倍、朝右 ±38 度）。舊的正面圓洞版（s2）仍保留，可當牆面上的破洞貼圖。
- 觸手很細（尖端近乎針尖），與打撈臂（粗短、深藍綠、有大吸盤）一眼可分；線條有細微起伏但最粗處只約畫面寬的四分之一，做網格變形時網格寬度請依實際粗細設定。
- 觸手根部是一個圓球頭，洞心的深黑可以蓋住它。
- 牆洞口的鋸齒外緣不是雜點，是設計。
