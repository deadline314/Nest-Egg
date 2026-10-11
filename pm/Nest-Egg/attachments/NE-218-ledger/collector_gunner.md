# collector_gunner（收帳人·槍手）部件帳本

由規格、外觀定義與配方產生；改了規格要重產。

- 來源：`art_src/characters/collector_gunner/base_rgba.png`，提示詞與種子在 `art_src/characters/collector_gunner/01_design/`（種子 21951）
- 底層圖：P；規格 `tools/comfyui/specs/collector_gunner_side.json`
- 骨架 `art/rigs/collector_gunner.json`；動作資料 `art/motion/collector_gunner.json`；貼圖密度每世界像素 20.0 像素

## 零件

| 顯示名稱 | 貼圖 | 尺寸 | 支點 | 骨頭 | 圖層 | 狀態 | 來源群組與切法 |
|---|---|---|---|---|---|---|---|
| arm_back_upper | arm_upper | [106, 214] | [47.84, 32.6] | arm_back_upper | -7 | 常態 | arm：shoulder→elbow |
| arm_back_lower | arm_lower | [89, 189] | [44.06, 12.04] | arm_back_lower | -7 | 常態 | arm：elbow→palm |
| hand_back | hand | [122, 70] | [18.3, 37.53] | hand_back | -6 | 常態 | arm：palm→fingertip |
| leg_back_upper | leg_upper | [176, 369] | [79.01, 93.71] | leg_back_upper | -5 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_back_lower | leg_lower | [111, 335] | [59.36, 12.04] | leg_back_lower | -5 | 常態 | body：knee→ankle，圓蓋 |
| foot_back | foot | [130, 169] | [42.1, 62.32] | foot_back | -5 | 常態 | body：ankle→toe，圓蓋 |
| pelvis | pelvis | [228, 203] | [113.92, 114.65] | hip | 0 | 常態 | body：waist→hip，圓蓋，前緣直線，認領無主像素 |
| torso | torso | [242, 338] | [122.95, 305.96] | chest | 1 | 常態 | body：waist→neck |
| leg_front_upper | leg_upper | [176, 369] | [79.01, 93.71] | leg_front_upper | 3 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_front_lower | leg_lower | [111, 335] | [59.36, 12.04] | leg_front_lower | 3 | 常態 | body：knee→ankle，圓蓋 |
| foot_front | foot | [130, 169] | [42.1, 62.32] | foot_front | 3 | 常態 | body：ankle→toe，圓蓋 |
| head | head | [152, 147] | [33.99, 167.55] | head | 5 | 常態 | head：head→head_top |
| arm_front_upper | arm_upper | [106, 214] | [47.84, 32.6] | arm_front_upper | 8 | 常態 | arm：shoulder→elbow |
| arm_front_lower | arm_lower | [89, 189] | [44.06, 12.04] | arm_front_lower | 8 | 常態 | arm：elbow→palm |
| hand_front | hand | [122, 70] | [18.3, 37.53] | hand_front | 10 | 常態 | arm：palm→fingertip |

## 接點

| 連接 | 關節座標（來源圖像素） | 兩側零件 | 補強 |
|---|---|---|---|
| 頭－頸－胸 | [405, 188] | torso－head | 重疊（torso 藏在 head 下）、重疊（torso 藏在 head 下） |
| 胸－腰－骨盆 | [423, 417] | torso－pelvis | 相鄰重疊（seam） |
| 肩 | [348, 232] | torso－arm_upper | 重疊（torso 藏在 arm_upper 下） |
| 肘 | [344, 400] | arm_upper－arm_lower | 相鄰重疊（seam） |
| 腕 | [368, 562] | arm_lower－hand | 相鄰重疊（seam） |
| 髖 | [432, 540] | pelvis－leg_upper | 圓蓋（pelvis）、圓蓋（leg_upper） |
| 膝 | [396, 800] | leg_upper－leg_lower | 相鄰重疊（seam） |
| 踝 | [362, 1073] | leg_lower－foot | 圓蓋（leg_lower）、圓蓋（foot） |
