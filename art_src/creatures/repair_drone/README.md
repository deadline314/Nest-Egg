# repair_drone（維修機）立繪

票：NE-91。第二章。白色加薄荷綠外殼，綠色光束發射器。

## 最終圖

| 部件 | 檔名 | 種子 | 尺寸 | 說明 |
|---|---|---|---|---|
| 本體 | `body_s2.png` | 2 | 832x832 | 嚴格側面（平視）的蛋形白綠機身，朝右；前方（右）深色面罩加兩顆綠色小眼，前下方綠色光束發射器鏡頭，頂上一根細直天線，肚子底下的懸浮墊是邊緣朝向鏡頭的扁平圓盤，身側正中一顆深灰肩關節座（圓心約 (340, 430)、半徑約 80）；不含手臂 |
| 機械臂 | `arm_s3.png` | 3 | 512x1216 | 單條細機械臂，嚴格垂直朝下、各節在同一條垂直線上：肩關節圓盤（圓心約 (268, 77)、半徑約 48）、漸縮的上臂、肘關節圓盤、前臂、腕關節、筆直的焊槍與綠色硬邊發光槍口；沒有軟管與電纜。兩條手臂用同一張（鏡像或錯開角度） |

舊圖保留（不採用）：`body_s1_old.png`（原 seed 1：略帶俯視的圓蛋，懸浮墊看得到頂面）、`arm_s1_old.png`（原 seed 1：焊槍是彎曲軟管，不垂直）。未採用的候選：`arm_s2.png`（seed 2：全直但三節香腸狀、焊槍光暈沒有輪廓）。

## 重畫紀錄（2026-10-04，NE-91 補強）

- 本體重畫 1 次：加入「平視正側面、完全沒有俯視、懸浮墊邊緣朝鏡頭、側面只有一顆肩關節座」後，seed 2 一次就是嚴格側面，採用。
- 機械臂重畫 2 次：seed 2 全直但太單調；seed 3 加上「黑色粗輪廓、關節圓盤、面板線與螺栓、不要軟管」後，採用。
- 邊緣檢查：邊緣比內側亮的像素比例，本體 5.9%、機械臂 1.6%（舊本體 9.7%、舊機械臂 1.0%）；疊在深淺底色放大看沒有光暈。
- 拼合：示意見 `pm/Nest-Egg/images/NE-91-redraw-repair-drone.png`（機械臂縮放 0.4，肩關節圓盤圓心對到本體肩關節座圓心；遠側臂調暗並錯開）。新舊對照見 `pm/Nest-Egg/images/NE-91-redraw-compare.png`。

## 提示詞（英文原文）

body（最終，seed 2）：
> A friendly rounded maintenance repair drone drawn as a flat orthographic side elevation, like a technical blueprint profile: the camera is exactly level with the drone, perfectly horizontal, absolutely NO view from above and NO three-quarter perspective, we see only the drone's left flank. A smooth egg-shaped white body with mint-green panel stripes and dark grey joints. Its front faces right: at the front-right end there is a dark visor window with two small green glowing eyes seen in profile, and a round green glowing beam-emitter lens on the front underside. A thin antenna rises straight up from the top. A thin flat disc-shaped hover pad under the belly, seen exactly edge-on as a narrow horizontal band. One round dark-grey shoulder socket disc on the flank in the middle of the body where a robotic arm attaches (the arm itself is NOT drawn). No arms, no wings, no legs, no beam. Centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.

arm（最終，seed 3）：
> A single slender robotic arm of a friendly maintenance repair drone, drawn as a flat orthographic side elevation like a technical blueprint profile, hanging perfectly straight down and perfectly vertical along the center line of the picture. From top to bottom: a round dark-grey shoulder joint disc with a ring and a bolt in the center, a straight tapered upper arm with a white armored shell, a mint-green stripe, panel lines and small bolts, a large round dark-grey elbow joint disc, a straight forearm with a white armored shell, a mint-green stripe and panel lines, a dark-grey wrist joint, and a compact welding torch pointing straight down with a hard-edged bright green glowing nozzle. Bold clean black outlines on every part. White shells, mint-green stripes, dark grey joints, the same colors as a white and mint-green egg-shaped drone. Only one arm, all segments exactly in one vertical line, flat side view with no perspective, no curved hoses and no loose cables. Nothing else in the picture: no body, no ground, no shadow, no text, no other objects.

舊版（seed 1，不採用）：
> body：A friendly rounded maintenance repair drone: a smooth egg-shaped white body with mint-green panel accents and dark grey joints, a wide dark visor with two small green glowing eyes on its front (right side), a small antenna on top, and a round green beam-emitter lens mounted on the front underside that glows bright green. A small hover pad on the underside. Two empty round shoulder sockets on the body side where robotic arms would attach (the arms themselves are NOT drawn). No arms, no wings, no legs, no beam. Strict side view facing right, centered in the picture. Nothing else in the picture: no ground, no shadow, no text, no other objects.
>
> arm：A single slender robotic arm of a maintenance repair drone, hanging straight down: a round shoulder joint disc at the top, a thin upper arm, an elbow joint, a thin forearm, and at the bottom tip a small welding torch with a bright green glowing nozzle. White body shells with mint-green accents and dark grey joints and cables. Only one arm, perfectly vertical, symmetric and centered in the picture, flat side view. Nothing else in the picture: no body, no ground, no shadow, no text, no other objects.

## 取捨與注意

- 新版比舊版細節少、較接近圖示風格，但外形嚴格側面、關節位置明確，做骨架（肩、肘、腕）比較好抓。
- 本體下半是青藍漸層，不是舊版的純白；與探照無人機（深藍、黃燈）、監視蜂（藍、紅眼）仍一眼可分。
- 本體只畫近側一顆肩關節座；遠側那條手臂要在遊戲裡把近側臂複製、調暗並錯開位置來表現。
- 兩張圖各自填滿畫面，相對大小依設骨架時的遊戲尺寸縮放。
