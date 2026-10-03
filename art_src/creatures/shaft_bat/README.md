# shaft_bat（井道蝙蝠機）立繪

票：NE-93。第二章升降井，翼式飛行。鋼灰機身加紫色發光縫與紅色眼睛（紅眼是設計文件規定的預兆燈），翅膀是深靛紫膜。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體 | `body_s5.png` | 5 | 1216x832 | 滑翔姿勢的蝙蝠機：**淺鋼藍灰**的細長流線機身（像戰鬥機機身），大耳、尖吻與金屬小牙、紅色發光眼、背脊一排小刺、細長尾巴加三角尾翼、兩隻縮在腹下的爪；背上近頸處一個空的圓形肩座（側面只看得到近側這一個）；沒有翅膀 |
| 翅膀（單側） | `wing_s1.png` | 1 | 832x1216 | 展開朝上的單片翅膀：底端圓形肩關節、上臂骨、肘、前臂骨、四根指骨撐起的靛紫色扇形膜（邊緣呈鋸齒、有小破洞）；兩側翅膀用同一張（後側翅可調暗或鏡像） |

不採用的候選：`body_s1.png`（seed 1）、`body_s2.png`（seed 2）、`body_s3.png`（seed 3，舊版採用，近黑鋼灰，暗處對比低）、`body_s4.png`（seed 4，亮但圓胖像犰狳，不夠兇）。

## 重畫紀錄

- 本體重畫 2 次（共 3 張）：
  - seed 1：造型兇，但機身接近純黑，在深色背景上看不清輪廓與細節，且只有一個肩座。
  - seed 2：改提示詞要求中間色調的鋼灰紫，結果整隻變成飽和的紫色、造型圓胖像玩具，不夠兇。
  - seed 3：深鋼灰帶一點藍、面板線清楚、紅眼與紫色發光縫，輪廓與細節都看得清楚，選用。
- 翅膀 0 次。
- 2026-10-04 補強（本體偏暗）：s3 在暗背景上對比低。改成「淺鋼藍灰、面板線清楚、亮灰高光」重畫 2 次：seed 4 夠亮但機身圓胖像犰狳；seed 5 加上「細長流線、像戰鬥機機身」後兇悍、輪廓清楚，採用。
- 2026-10-04 全部立繪清過背景：Qwen 在「透明背景」上會留一層極淡的紫色薄霧（alpha 1～8），已清成全透明（`creature_art.py` 之後生成的圖會自動清；舊圖用 `--clean` 補清）。

## 提示詞（英文原文）

body（最終，seed 5，2026-10-04）：
> The body of a menacing flying metal bat machine seen from the side facing right, in a gliding pose: a SLIM streamlined aerodynamic fuselage, long and narrow like a fighter jet body, made of light steel-blue-grey armor plates with clearly visible panel lines and bright light grey highlights, readable against a dark background, a large bat-like head at the front (right side) with two tall pointed ears, a sharp snout with small metal fangs and a glowing red eye, a ribbed spine with small spikes, a long thin tail ending in a small triangular tail fin at the back (left), and two small clawed feet tucked under the belly. On the upper back, just behind the neck, one round empty shoulder socket disc where a wing attaches (the wings are NOT drawn). Bright violet glowing seams. No wings, no membranes. Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

body（seed 3，舊版）：
> The body of a menacing flying metal bat machine seen from the side facing right, in a gliding pose: a compact rounded torso made of dark steel-grey armor plates with a slight blue tint and clearly visible panel lines and light grey highlights, a large bat-like head at the front (right side) with two tall pointed ears, a sharp snout with small metal fangs and a glowing red eye, a ribbed spine, a long thin tail ending in a small triangular tail fin at the back (left), and two small clawed feet tucked under the belly. On the back are two empty round shoulder sockets where the wings attach (the wings are NOT drawn). Thin violet glowing seams. No wings, no membranes. Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

wing：
> A single spread bat wing of a flying metal bat machine, held open and pointing upward: a round shoulder joint at the bottom center, a short upper-arm bone rising to an elbow joint, then a forearm bone continuing up, with four slender finger-like ribs fanning out from the wrist, supporting a thin scalloped membrane stretched between them. Dark steel-grey metal bones with violet glowing seams, and a dark indigo-violet translucent membrane with faint lighter ribs and small tears at the scalloped edge. Only one wing, flat 2D side view, centered in the picture. Nothing else in the picture: no body, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 嚴格側面只會看到近側一個肩座，這是正確的（遠側肩座本來就被身體擋住），所以不再要求畫兩個：翅膀掛在這個肩座（圖座標約 (736, 406)）上，遠側翅膀用同一張調暗（0.55 倍亮度）、往尾端錯開約 40 像素疊在身體後面。新拼合示意見 `pm/Nest-Egg/images/NE-93-assembly-v2.png`（翅膀縮放 0.55 倍、近側翅旋轉 +6 度、遠側翅旋轉 -14 度）。
- 翅膀圖的肩關節在畫面左下（約 324, 1101），整片翅膀微向左（後方）傾斜，上臂骨與指骨是分明的兩節，可以切成「上臂、前臂加膜」兩節骨頭。
- 新本體是淺鋼藍灰，暗背景上輪廓清楚，也不再靠紅眼才能辨識；翅膀仍是深靛紫膜，與機身形成明暗對比。
- 與攀牆者（青綠色壁虎）、纏絲（暗紅黑）不撞色：這隻是鋼灰加靛紫。
