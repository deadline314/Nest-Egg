# mimic（偽裝箱）立繪

票：NE-91。第一章。生鏽貨箱，張開時紅色內裡加白牙與舌頭。

## 最終圖

| 狀態 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 閉合 | `closed_s4.png` | 4 | 1248x832（編輯輸出的寬度比張開圖多 32，左上角原點相同，座標不用位移） | 由張開圖用 Qwen 編輯「闔上箱蓋並封住前端的嘴」得到的嚴格側面（平視）：箱蓋闔上，箱蓋與箱身之間一條紅色發光縫，縫裡只露出幾點牙尖，右端（嘴那一端）是封起來的鏽鋼端板；已做邊緣去光暈（未處理的原始輸出是 `closed_s4_raw.png`） |
| 張開 | `open_s1.png` | 1 | 1216x832 | 同一種貨箱，箱蓋以左後方為鉸鏈掀開約 60 度，箱內與蓋內是紅色肉質內裡，箱口與蓋口各有一排白色尖牙，前方（右）伸出粉紅色長舌 |

兩張**同畫布、同座標**：箱身左緣都在 x=226，箱腳底緣 y=748（張開）與 751（閉合），箱身與箱腳大小一致，可以直接疊在一起切換（拼合示意見 `pm/Nest-Egg/images/NE-91-redraw-mimic.png`）。閉合圖的箱身右緣比張開圖多約 30 像素（封起來的端板）。

舊圖保留（不採用）：`closed_s1_old.png`（原 seed 1：略帶前視、看得到箱蓋頂面、箱身比例與張開圖不同）。其他未採用的候選：`closed_s2.png`（seed 2 文生圖：嚴格側面，但箱身過長過扁、比例與張開圖差很多）、`closed_s3.png`（seed 3 編輯：箱蓋闔上，但前端的嘴仍張開露牙，邊緣較乾淨）、`closed_s4_raw.png`（seed 4 未處理的輸出，邊緣有一圈淺色光暈）。

## 重畫紀錄（2026-10-04，NE-91 補強）

- 閉合圖重畫 3 次：
  1. seed 2：文生圖，加「平視、完全看不到蓋頂、箱身長寬比 2.7」。側面是嚴格的，但箱身實際約 3.5:1、蓋子太薄，與張開圖的比例對不上。
  2. seed 3：改用編輯模式，以 `open_s1.png` 當參考圖，要求闔上箱蓋、舌頭收回、其餘不動。箱身、箱腳、鏽斑與位置和張開圖完全一致，箱蓋闔好，但前端的嘴還張著。
  3. seed 4：以 seed 3 的輸出當參考圖，要求封住前端的嘴。得到偽裝用的封閉貨箱，只剩縫裡的牙尖；採用。輸出的外緣有一圈淺色光暈（邊緣比內側亮的像素 71.6%），用 `tools/comfyui/refine_parts.py` 的 `defringe`（寬度 3）處理後降到 4.0%；留有原圖 `closed_s4_raw.png`。
- 編輯模式不在 `creature_art.py` 內（它只做文生圖），這次用同一個 `comfy_api.qwen(images=[...])` 與同樣的 RGBA 包裝句，寬高 1216x832。

## 提示詞（英文原文）

closed（最終，seed 4；編輯模式。參考圖：seed 3 的輸出；seed 3 的參考圖：`open_s1.png`。每句前面加 `This is an RGBA image with transparency.`，後面加 `The image has alpha channel and the background is transparent.`）：

seed 3：
> Close the crate completely: the heavy lid comes down flat onto the box and the box is shut tight, the red flesh interior is no longer visible and the tongue is pulled back inside. Along the seam between the lid and the box there is only a thin glowing red crack, with the tips of a few small white teeth just peeking out of the seam at the right end. Keep the crate body, its size and proportions, the rust, the corner brackets, the hazard stripe, the four feet, the art style, the outlines, the colors and the position exactly unchanged. Strict flat side view facing right, no view from above.

seed 4：
> Shut the front mouth of the crate too: the open fanged maw on the right end face is closed and sealed by a plain rusty steel end panel like the other sides, with a bolted frame; only a few tiny white teeth tips peek out of the thin glowing red seam where the lid meets the box. No open mouth, no big teeth, no tongue. Keep the lid, the crate body, its size and proportions, the rust, the corner brackets, the hazard stripe, the four feet, the art style, the outlines, the colors and the position exactly unchanged. Strict flat side view facing right.

seed 2（文生圖，不採用）：
> A heavy rusty steel cargo crate that is secretly a monster mimic, completely CLOSED, drawn as a flat orthographic side elevation like a technical blueprint profile: the camera is exactly level with the crate, absolutely NO view from above, the top surface of the lid is NOT visible at all, we see only the long side of the crate as a flat rectangle. The crate body is a long low dark grey-black steel box about 2.7 times as long as it is tall, with corrugated panels, orange-brown rust patches, peeling paint, bolted corner brackets, steel straps and a yellow-black hazard stripe band on the side panel. A flat slab-shaped lid sits closed on top of the box, as thick as about one quarter of the box height, with a thin glowing red crack along the seam between lid and box and a few tiny sharp white teeth just peeking out of the seam at the right end. Four short stubby rusty metal feet under the box, two visible. The front of the crate (the mimic's mouth end) is on the right. Centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

open（seed 1，未重畫）：
> The same heavy rusty steel cargo crate as a monster mimic with its mouth wide OPEN, seen from the side: a wide rectangular dark metal box with corrugated panels, orange-brown rust patches, dented corners, bolted corner brackets and stenciled warning stripes, standing on four short stubby feet. The heavy lid is hinged at the left rear edge and flung wide open upward, tilted back about 60 degrees. The inside of the box and the underside of the lid are glowing red flesh-like interior, and both the rim of the box and the rim of the lid have a row of sharp white fangs. A long pink-red tongue hangs out of the front (right side) of the box. Strict side view facing right, the front of the crate is on the right. Nothing else in the picture: no ground, no shadow, no text, no other objects.

舊 closed（seed 1，不採用）：
> A heavy rusty steel cargo crate sitting on the ground, completely CLOSED, seen from the side: a wide rectangular metal box with a separate hinged lid on top, corrugated panels, orange-brown rust patches and peeling paint, dented corners, bolted corner brackets, and stenciled warning stripes. A thin crack of red glow shows along the seam between lid and box, with a few tiny white teeth just barely visible in the seam. Four short stubby metal feet at the bottom. Strict side view facing right, the front of the crate is on the right. Nothing else in the picture: no ground, no shadow, no text, no other objects.

## 取捨與注意

- 閉合圖與張開圖的箱身、箱腳一致，所以「閉合 ↔ 張開」的切換可以直接疊同一張畫布；要做開合動畫仍得沿鉸鏈處（圖左側、箱身上緣左端附近）把張開圖的箱蓋切出來。
- 張開圖的箱蓋與箱身在鉸鏈處相連（alpha 是同一個連通區），蓋子的內裡與牙齒是朝向觀看者的，切開後箱口內裡（紅色肉面）在箱身這邊。
- 閉合圖的端板畫成略斜的封板（看得到一點點端面），不是百分之百的正投影；整體是平視的側面，看不到蓋頂。
- 閉合圖比舊版亮、鏽橘更多（舊版整體近黑），靠鏽橘、黃黑警示條與橫向紅色縫光辨識。
