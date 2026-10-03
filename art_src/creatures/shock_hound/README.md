# shock_hound（電擊犬）立繪

票：NE-91。第一章。暗灰機械犬加青色電弧與青色眼睛。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體（含頭與四條腿） | `body_s2.png` | 2 | 1216x832 | 低頭潛行姿勢的機械犬，金屬牙，青色眼，青色電弧沿背與肩跳動；沒有尾巴 |
| 電極尾 | `tail_s1.png` | 1 | 1216x832 | 水平朝左伸出的分節機械尾，粗根在右端，尖端是叉形電極加青色火花 |

不採用的候選：`body_s1.png`（seed 1，姿勢更低伏，但畫面左側有一個約 150 像素的游離小黑塊，且電弧光暈範圍很大）。

## 重畫紀錄

- 本體生成 2 次（seed 1、seed 2）。seed 1 合格但有游離小黑塊，為了乾淨再畫一次；seed 2 的姿勢站得稍高、腿較長，電弧是清楚的細線，選 seed 2。
- 尾巴 0 次重畫。

## 提示詞（英文原文）

body（兩個 seed 同一句）：
> A low-crouching robotic guard dog with a long lean body, in a stalking pose with its head lowered, standing on four mechanical legs. Dark charcoal-grey metal armor plating with exposed black cable bundles, a angular dog-like head with a snarling jaw of metal teeth and glowing cyan eyes, small cyan electric arcs crackling along its spine and shoulders and leg joints. The dog has NO tail (the tail is drawn separately; leave a small empty tail socket at the rear). Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

tail：
> The tail of a robotic guard dog: a long segmented mechanical tail extending horizontally to the left, thick round root joint at the right end and tapering to the left, ending in a forked metal electrode tip with a bright cyan electric spark between the two prongs. Dark charcoal-grey metal armor segments with exposed black cables and small cyan glowing joints. Only the tail, perfectly horizontal and centered in the picture, flat side view. Nothing else in the picture: no dog body, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 本體的電弧是獨立小島（alpha 連通區），不是雜點，不要用「刪除小碎塊」的步驟把它清掉。
- 本體畫面沒有明確的尾巴座，尾巴要接在背部後端（圖左上方，約身體最後端的脊線處）。
- 尾巴的根部球偏大、尾長與身體差不多（圖寬 1160 像素對身體 1160 像素），縮放時以遊戲尺寸為準，不要照原圖比例接。
- 深色機身在深色背景上對比偏低，關卡裡建議靠青色電弧與眼睛辨識。
