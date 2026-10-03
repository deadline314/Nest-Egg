# rail_cannon（吊軌砲）立繪

票：NE-93。第二章轉運站，天花板軌道上的砲。近黑的鋼灰機身加黃黑警示條與紅色鏡頭／砲口環。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 滑座 | `slider_s2.png` | 2 | 832x832 | 頂端是一小段鋼軌與帶兩顆可見滾輪的夾持塊（橘色火花），下方懸吊著**中灰鋼色**的裝甲滑座，中間一顆紅色感測鏡頭與黃黑斜紋，最下方是圓形砲管樞軸座與一小段樞軸栓；沒有砲管 |
| 砲管 | `barrel_s3.png` | 3 | 1216x832 | 水平朝右的重型砲管組：左端圓形樞軸轂（帶螺栓）、笨重砲尾、黃黑警示條、細長砲身加散熱環、右端砲口加紅色發光環；**亮銀灰色**金屬，黑色粗輪廓 |

不採用的候選：`slider_s1.png`（seed 1，近黑鋼灰）、`barrel_s1.png`（seed 1）、`barrel_s2.png`（seed 2，近黑鋼灰，邊緣乾淨但太暗）。

## 重畫紀錄

- 砲管重畫 1 次：seed 1 的外輪廓沒有黑邊，直線邊緣上有一條很細的淺灰亮邊（邊緣淺色光暈，量化上有約 47% 的邊緣半透明像素比內側亮）。seed 2 加上「粗黑輪廓」的描述後邊緣乾淨（約 0.3%），選用。
- 滑座 0 次（原版）。
- 2026-10-04 補強對比：舊的兩張近黑，在暗處看不到輪廓。滑座與砲管都改成「中灰與亮銀灰金屬、淺灰高光、黑粗輪廓」，各重畫 1 次（滑座 seed 2、砲管 seed 3）一次合格，黃黑條與紅色鏡頭／砲口環保留。
- 2026-10-04 全部立繪清過背景：Qwen 在「透明背景」上會留一層極淡的紫色薄霧（alpha 1～8），已清成全透明（`creature_art.py` 之後生成的圖會自動清；舊圖用 `--clean` 補清）。

## 提示詞（英文原文）

slider：
> The sliding carriage of a ceiling-rail-mounted cannon, seen from the side: at the top a wide flat roller-wheel clamp block with four small steel wheels that grips a ceiling rail (a short piece of the dark steel rail is visible across the very top), below it a compact armored carriage body hanging downward, with yellow-and-black hazard stripes, a glowing red sensor lens in the middle, and a round pivot socket at the bottom center where a gun barrel would attach (the barrel itself is NOT drawn). Dark gunmetal steel with brass-yellow hazard marks and tiny orange sparks at the wheels. No barrel, no laser beam. Flat strict side view, centered in the picture. Nothing else in the picture: no ceiling, no ground, no shadow, no text, no other objects.

barrel（最終，seed 2）：
> A single heavy cannon barrel assembly of a ceiling-rail cannon, perfectly horizontal and pointing to the right, drawn with a thick black outline all around its silhouette: a thick round pivot hub with a bolted ring at the left end, a bulky armored breech section with a yellow-and-black hazard band, a long straight barrel with cooling rings, and a muzzle at the right end with a dark round opening and a small glowing red lens ring. Dark gunmetal steel with brass-yellow hazard marks and a few red indicator lights. Only the barrel assembly, flat side view, centered in the picture. Nothing else in the picture: no carriage, no rail, no laser beam, no ground, no shadow, no text, no other objects.

新版提示詞（與舊版差在材質與亮度，其餘相同）：

slider（seed 2）：
> The sliding carriage of a ceiling-rail-mounted cannon, seen from the side: at the top a wide flat roller-wheel clamp block with four small steel wheels that grips a ceiling rail (a short piece of the steel rail is visible across the very top), below it a compact armored carriage body hanging downward, with yellow-and-black hazard stripes, a glowing red sensor lens in the middle, and a round pivot socket at the bottom center where a gun barrel would attach (the barrel itself is NOT drawn). Medium steel-grey and bright brushed-silver metal with light grey highlights, clearly NOT black and not dark, readable against a dark background, with brass-yellow hazard marks and tiny orange sparks at the wheels. No barrel, no laser beam. Flat strict side view, centered in the picture. Nothing else in the picture: no ceiling, no ground, no shadow, no text, no other objects.

barrel（最終，seed 3）：
> A single heavy cannon barrel assembly of a ceiling-rail cannon, perfectly horizontal and pointing to the right, drawn with a thick black outline all around its silhouette: a thick round pivot hub with a bolted ring at the left end, a bulky armored breech section with a yellow-and-black hazard band, a long straight barrel with cooling rings, and a muzzle at the right end with a dark round opening and a small glowing red lens ring. Medium steel-grey and bright brushed-silver metal with light grey highlights, clearly NOT black and not dark, readable against a dark background, with brass-yellow hazard marks and a few red indicator lights. Only the barrel assembly, flat side view, centered in the picture. Nothing else in the picture: no carriage, no rail, no laser beam, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 滑座是左右對稱、從「垂直於軌道」的方向看的圖，鋼軌橫跨上緣；新版滑座底部樞軸座約在 (429, 690)，新版砲管圖樞軸轂中心約在 (140, 425)。拼合示意見 `pm/Nest-Egg/images/NE-93-assembly.png`（砲管縮放 0.5 倍、朝右下旋轉 28 度，砲管畫在滑座後面）。
- 新版改成中灰與亮銀灰，暗處也看得到輪廓；黃黑條、紅鏡頭、紅砲口環仍是辨識重點。與哨戒砲台（灰藍、紅鏡頭）的外型差很多（吊掛式、有鋼軌），兩者不在同一章。新拼合示意見 `pm/Nest-Egg/images/NE-93-assembly-v2.png`（砲管縮放 0.5 倍、朝右下旋轉 25 度）。
- 紅色雷射線沒有畫，之後用特效。
