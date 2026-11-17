# sweeper（清掃兵）部件帳本

由規格、外觀定義與配方產生；改了規格要重產。

- 來源：`art_src/characters/sweeper/base_rgba.png`，提示詞與種子在 `art_src/characters/sweeper/01_design/`（種子 21941）
- 底層圖：P；規格 `tools/comfyui/specs/sweeper_side.json`
- 骨架 `art/rigs/sweeper.json`；動作資料 `art/motion/sweeper.json`；貼圖密度每世界像素 20.0 像素

## 零件

| 顯示名稱 | 貼圖 | 尺寸 | 支點 | 視覺位移（世界像素） | 骨頭 | 圖層 | 狀態 | 來源群組與切法 |
|---|---|---|---|---|---|---|---|---|
| arm_back_upper | arm_upper | [104, 211] | [52.07, 36.39] | [0, 0] | arm_back_upper | -7 | 常態 | arm：shoulder→elbow |
| arm_back_lower | arm_lower | [97, 185] | [48.42, 12.13] | [0, 0] | arm_back_lower | -7 | 常態 | arm：elbow→palm |
| hand_back | hand | [132, 73] | [19.86, 33.98] | [0, 0] | hand_back | -6 | 常態 | arm：palm→fingertip |
| leg_back_upper | leg_upper | [178, 347] | [95.71, 87.0] | [0, 0] | leg_back_upper | -5 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_back_lower | leg_lower | [117, 324] | [69.79, 12.15] | [0, 0] | leg_back_lower | -5 | 常態 | body：knee→ankle，圓蓋 |
| foot_back | foot | [159, 139] | [46.21, 52.43] | [0, 0] | foot_back | -5 | 常態 | body：ankle→toe，圓蓋 |
| pelvis | pelvis | [181, 199] | [94.36, 111.66] | [0, 0] | hip | 0 | 常態 | body：waist→hip，圓蓋，前緣直線，認領無主像素 |
| torso | torso | [258, 325] | [157.73, 293.88] | [0, 0] | chest | 1 | 常態 | body：waist→neck |
| leg_front_upper | leg_upper | [178, 347] | [95.71, 87.0] | [0, 0] | leg_front_upper | 3 | 常態 | body：hip→knee，圓蓋，前緣直線 |
| leg_front_lower | leg_lower | [117, 324] | [69.79, 12.15] | [0, 0] | leg_front_lower | 3 | 常態 | body：knee→ankle，圓蓋 |
| foot_front | foot | [159, 139] | [46.21, 52.43] | [0, 0] | foot_front | 3 | 常態 | body：ankle→toe，圓蓋 |
| head | head | [163, 185] | [52.9, 181.87] | [0, 0] | head | 5 | 常態 | head：head→head_top |
| arm_front_upper | arm_upper | [104, 211] | [52.07, 36.39] | [0, 0] | arm_front_upper | 8 | 常態 | arm：shoulder→elbow |
| arm_front_lower | arm_lower | [97, 185] | [48.42, 12.13] | [0, 0] | arm_front_lower | 8 | 常態 | arm：elbow→palm |
| hand_front | hand | [132, 73] | [19.86, 33.98] | [0, 0] | hand_front | 10 | 常態 | arm：palm→fingertip |

## 接點

| 連接 | 關節座標（來源圖像素） | 兩側零件 | 補強 |
|---|---|---|---|
| 頭－頸－胸 | [382, 214] | torso－head | 重疊（torso 藏在 head 下）、重疊（torso 藏在 head 下） |
| 胸－腰－骨盆 | [387, 441] | torso－pelvis | 相鄰重疊（seam） |
| 肩 | [354, 251] | torso－arm_upper | 重疊（torso 藏在 arm_upper 下） |
| 肘 | [355, 417] | arm_upper－arm_lower | 相鄰重疊（seam） |
| 腕 | [394, 577] | arm_lower－hand | 相鄰重疊（seam） |
| 髖 | [398, 564] | pelvis－leg_upper | 圓蓋（pelvis）、圓蓋（leg_upper） |
| 膝 | [374, 818] | leg_upper－leg_lower | 相鄰重疊（seam） |
| 踝 | [344, 1096] | leg_lower－foot | 圓蓋（leg_lower）、圓蓋（foot） |

## 姿勢替換與眼睛

沒有額外姿勢貼圖替換。

尺寸、支點、位移與姿勢替換依目前正式外觀資料核對；來源座標依目前角色規格核對。法線沿用同名 `_n` 貼圖；實際載入驗證另見本票交付紀錄。
