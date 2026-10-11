# collector_brute（收帳人·打手）部件帳本

由規格、外觀定義與配方產生；改了規格要重產。

- 來源：`art_src/characters/collector_brute/base_rgba.png`，提示詞與種子在 `art_src/characters/collector_brute/01_design/`（種子 21961）
- 底層圖：P；規格 `tools/comfyui/specs/collector_brute_side.json`
- 骨架 `art/rigs/collector_brute.json`；動作資料 `art/motion/collector_brute.json`；貼圖密度每世界像素 18.82 像素

## 零件

| 顯示名稱 | 貼圖 | 尺寸 | 支點 | 骨頭 | 圖層 | 狀態 | 來源群組與切法 |
|---|---|---|---|---|---|---|---|
| arm_back_upper | arm_upper | [170, 242] | [78.21, 56.17] | arm_back_upper | -7 | 常態 | arm：shoulder→elbow |
| arm_back_lower | arm_lower | [145, 189] | [72.99, 12.25] | arm_back_lower | -7 | 常態 | arm：elbow→palm |
| hand_back | hand | [148, 105] | [26.62, 49.95] | hand_back | -6 | 常態 | arm：palm→fingertip |
| leg_back_upper | leg_upper | [312, 407] | [166.44, 144.01] | leg_back_upper | -5 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_back_lower | leg_lower | [254, 306] | [106.76, 12.01] | leg_back_lower | -5 | 常態 | body：knee→ankle，圓蓋 |
| foot_back | foot | [220, 188] | [74.0, 89.0] | foot_back | -5 | 常態 | body：ankle→toe，圓蓋 |
| pelvis | pelvis | [360, 269] | [176.0, 137.0] | hip | 0 | 常態 | body：waist→hip，圓蓋，前緣直線，認領無主像素 |
| torso | torso | [372, 397] | [179.0, 365.0] | chest | 1 | 常態 | body：waist→neck |
| leg_front_upper | leg_upper | [312, 407] | [166.44, 144.01] | leg_front_upper | 3 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_front_lower | leg_lower | [254, 306] | [106.76, 12.01] | leg_front_lower | 3 | 常態 | body：knee→ankle，圓蓋 |
| foot_front | foot | [220, 188] | [74.0, 89.0] | foot_front | 3 | 常態 | body：ankle→toe，圓蓋 |
| head | head | [156, 146] | [61.0, 178.0] | head | 5 | 常態 | head：head→head_top |
| arm_front_upper | arm_upper | [170, 242] | [78.21, 56.17] | arm_front_upper | 8 | 常態 | arm：shoulder→elbow |
| arm_front_lower | arm_lower | [145, 189] | [72.99, 12.25] | arm_front_lower | 8 | 常態 | arm：elbow→palm |
| hand_front | hand | [148, 105] | [26.62, 49.95] | hand_front | 10 | 常態 | arm：palm→fingertip |

## 接點

| 連接 | 關節座標（來源圖像素） | 兩側零件 | 補強 |
|---|---|---|---|
| 頭－頸－胸 | [383, 207] | torso－head | 重疊（torso 藏在 head 下）、重疊（torso 藏在 head 下） |
| 胸－腰－骨盆 | [395, 477] | torso－pelvis | 相鄰重疊（seam） |
| 肩 | [310, 239] | torso－arm_upper | 重疊（torso 藏在 arm_upper 下） |
| 肘 | [306, 411] | arm_upper－arm_lower | 相鄰重疊（seam） |
| 腕 | [352, 567] | arm_lower－hand | 相鄰重疊（seam） |
| 髖 | [402, 622] | pelvis－leg_upper | 圓蓋（pelvis）、圓蓋（leg_upper） |
| 膝 | [350, 866] | leg_upper－leg_lower | 相鄰重疊（seam） |
| 踝 | [314, 1091] | leg_lower－foot | 圓蓋（leg_lower）、圓蓋（foot） |
