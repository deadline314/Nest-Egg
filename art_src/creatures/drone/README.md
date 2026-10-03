# drone（監視蜂）立繪

票：NE-91。第一章。灰藍機身加紅色單眼。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體 | `body_s1.png` | 1 | 1216x832 | 蜂腹式機身，前方（右）圓形頭艙與紅色單眼，尾端有針狀噴嘴；不含翅膀與腳 |
| 翅膀 | `wing_s1.png` | 1 | 832x832 | 單片薄翼，朝上，鉸鏈在畫面下方中央；兩對翅膀用同一張複製（後翼可調暗或縮小） |

重畫次數：0（兩張都是第一次就合格）。

## 提示詞（英文原文，工具會自動加上風格句與 RGBA 包裝）

body：
> A small hovering surveillance drone with a wasp-like body: a round head pod at the front (right side) carrying one large glowing red camera eye, a narrow waist, and a bulbous tapered segmented abdomen at the rear ending in a short stinger-like nozzle with a small red light. Matte blue-grey armored plating with dark steel panels and thin red glowing seams. The drone has NO wings and NO legs (wings are drawn separately). Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

wing：
> A single thin insect-like mechanical wing of a small surveillance drone, in the shape of a long narrow leaf, pointing straight upward with its small round hinge joint at the bottom center. Pale blue-grey translucent membrane with a dark steel frame and fine vein lines, a thin red glowing rim light along the leading edge. Only one wing, flat side view, centered in the picture. Nothing else in the picture: no body, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 本體長寬比約 3.4:1（很扁長），`data/enemies/drone.tres` 的 `body_size` 是 20x14，之後設骨架時受擊框要另外對。
- 翅膀是細長葉形、淺藍灰膜加深色細框與紅色前緣細光；翅膀實際尺寸比本體小很多（高約 600 像素對本體寬約 1080 像素），縮放時照遊戲尺寸決定。
