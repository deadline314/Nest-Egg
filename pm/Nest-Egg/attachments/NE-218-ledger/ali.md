# ali（阿梨）部件帳本

由規格、外觀定義與配方產生；改了規格要重產。

- 來源：`art_src/characters/ali/base_rgba.png`，提示詞與種子在 `art_src/characters/ali/01_design/`（種子 21921）
- 底層圖：P；規格 `tools/comfyui/specs/ali_side.json`
- 骨架 `art/rigs/ali.json`；動作資料 `art/motion/ali.json`；貼圖密度每世界像素 20.0 像素

## 零件

| 顯示名稱 | 貼圖 | 尺寸 | 支點 | 骨頭 | 圖層 | 狀態 | 來源群組與切法 |
|---|---|---|---|---|---|---|---|
| arm_back_upper | arm_upper | [87, 195] | [41.44, 25.05] | arm_back_upper | -7 | 常態 | arm：shoulder→elbow |
| arm_back_lower | arm_lower | [54, 177] | [27.4, 11.66] | arm_back_lower | -7 | 常態 | arm：elbow→palm |
| hand_back | hand | [101, 54] | [15.55, 27.85] | hand_back | -6 | 常態 | arm：palm→fingertip |
| leg_back_upper | leg_upper | [162, 337] | [82.77, 75.57] | leg_back_upper | -5 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_back_lower | leg_lower | [120, 309] | [57.97, 12.01] | leg_back_lower | -5 | 常態 | body：knee→ankle，圓蓋 |
| foot_back | foot | [141, 138] | [41.38, 56.0] | foot_back | -5 | 常態 | body：ankle→toe，圓蓋 |
| pelvis | pelvis | [186, 178] | [83.57, 106.63] | hip | 0 | 常態 | body：waist→hip，圓蓋，前緣直線，認領無主像素 |
| torso | torso | [178, 323] | [88.91, 292.77] | chest | 1 | 常態 | body：waist→neck |
| leg_front_upper | leg_upper | [162, 337] | [82.77, 75.57] | leg_front_upper | 3 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_front_lower | leg_lower | [120, 309] | [57.97, 12.01] | leg_front_lower | 3 | 常態 | body：knee→ankle，圓蓋 |
| foot_front | foot | [141, 138] | [41.38, 56.0] | foot_front | 3 | 常態 | body：ankle→toe，圓蓋 |
| head | head | [147, 173] | [65.44, 176.32] | head | 5 | 常態 | head：head→head_top |
| arm_front_upper | arm_upper | [87, 195] | [41.44, 25.05] | arm_front_upper | 8 | 常態 | arm：shoulder→elbow |
| arm_front_lower | arm_lower | [54, 177] | [27.4, 11.66] | arm_front_lower | 8 | 常態 | arm：elbow→palm |
| hand_front | hand | [101, 54] | [15.55, 27.85] | hand_front | 10 | 常態 | arm：palm→fingertip |

## 接點

| 連接 | 關節座標（來源圖像素） | 兩側零件 | 補強 |
|---|---|---|---|
| 頭－頸－胸 | [398, 211] | torso－head | 重疊（torso 藏在 head 下）、重疊（torso 藏在 head 下） |
| 胸－腰－骨盆 | [406, 438] | torso－pelvis | 相鄰重疊（seam） |
| 肩 | [356, 257] | torso－arm_upper | 重疊（torso 藏在 arm_upper 下） |
| 肘 | [352, 425] | arm_upper－arm_lower | 相鄰重疊（seam） |
| 腕 | [378, 586] | arm_lower－hand | 相鄰重疊（seam） |
| 髖 | [411, 560] | pelvis－leg_upper | 圓蓋（pelvis）、圓蓋（leg_upper） |
| 膝 | [383, 824] | leg_upper－leg_lower | 相鄰重疊（seam） |
| 踝 | [354, 1094] | leg_lower－foot | 圓蓋（leg_lower）、圓蓋（foot） |
