# egret（鷺）部件帳本

由規格、外觀定義與配方產生；改了規格要重產。

- 來源：`art_src/characters/egret/base_rgba.png`，提示詞與種子在 `art_src/characters/egret/01_design/`（種子 21912）
- 底層圖：P；規格 `tools/comfyui/specs/egret_side.json`
- 骨架 `art/rigs/egret.json`；動作資料 `art/motion/egret.json`；貼圖密度每世界像素 19.55 像素

## 零件

| 顯示名稱 | 貼圖 | 尺寸 | 支點 | 骨頭 | 圖層 | 狀態 | 來源群組與切法 |
|---|---|---|---|---|---|---|---|
| arm_back_upper | arm_upper | [113, 214] | [55.1, 28.99] | arm_back_upper | -7 | 常態 | arm：shoulder→elbow |
| arm_back_lower | arm_lower | [115, 196] | [59.21, 12.08] | arm_back_lower | -7 | 常態 | arm：elbow→palm |
| hand_back | hand | [114, 74] | [20.1, 34.69] | hand_back | -6 | 常態 | arm：palm→fingertip |
| leg_back_upper | leg_upper | [198, 368] | [101.94, 93.12] | leg_back_upper | -5 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_back_lower | leg_lower | [144, 322] | [68.61, 12.04] | leg_back_lower | -5 | 常態 | body：knee→ankle，圓蓋 |
| foot_back | foot | [170, 143] | [43.0, 54.0] | foot_back | -5 | 常態 | body：ankle→toe，圓蓋 |
| pelvis | pelvis | [265, 207] | [151.0, 120.0] | hip | 0 | 常態 | body：waist→hip，圓蓋，前緣直線，認領無主像素 |
| torso | torso | [252, 354] | [144.0, 322.0] | chest | 1 | 常態 | body：waist→neck |
| leg_front_upper | leg_upper | [198, 368] | [101.94, 93.12] | leg_front_upper | 3 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_front_lower | leg_lower | [144, 322] | [68.61, 12.04] | leg_front_lower | 3 | 常態 | body：knee→ankle，圓蓋 |
| foot_front | foot | [170, 143] | [43.0, 54.0] | foot_front | 3 | 常態 | body：ankle→toe，圓蓋 |
| head | head | [170, 176] | [62.0, 193.0] | head | 5 | 常態 | head：head→head_top |
| arm_front_upper | arm_upper | [113, 214] | [55.1, 28.99] | arm_front_upper | 8 | 常態 | arm：shoulder→elbow |
| arm_front_lower | arm_lower | [115, 196] | [59.21, 12.08] | arm_front_lower | 8 | 常態 | arm：elbow→palm |
| hand_front | hand | [114, 74] | [20.1, 34.69] | hand_front | 10 | 常態 | arm：palm→fingertip |

## 接點

| 連接 | 關節座標（來源圖像素） | 兩側零件 | 補強 |
|---|---|---|---|
| 頭－頸－胸 | [412, 216] | torso－head | 重疊（torso 藏在 head 下）、重疊（torso 藏在 head 下） |
| 胸－腰－骨盆 | [422, 453] | torso－pelvis | 相鄰重疊（seam） |
| 肩 | [385, 259] | torso－arm_upper | 重疊（torso 藏在 arm_upper 下） |
| 肘 | [387, 431] | arm_upper－arm_lower | 相鄰重疊（seam） |
| 腕 | [426, 597] | arm_lower－hand | 相鄰重疊（seam） |
| 髖 | [428, 581] | pelvis－leg_upper | 圓蓋（pelvis）、圓蓋（leg_upper） |
| 膝 | [410, 842] | leg_upper－leg_lower | 相鄰重疊（seam） |
| 踝 | [386, 1108] | leg_lower－foot | 圓蓋（leg_lower）、圓蓋（foot） |
