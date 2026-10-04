class_name WorldLayers
extends RefCounted
## 圖層順序（z_index）：靜態場景一律畫在所有角色零件之下。
## 角色骨架的零件有自己的 z（art/characters/*/character.json），最低到 -9（後側的手、腳、頭髮），最高到 +12（外層裝甲、武器）；
## 背景若排在 -9 以上，後側的手腳就會被背牆、地形、裝飾蓋住（看起來只有一隻腳）。新增靜態場景圖層請排在 SCENERY_MAX 以下。

## 角色零件的 z 範圍（資料檢查用：測試會確認真實資料沒有超出）。
const CHARACTER_MIN_Z := -9
const CHARACTER_MAX_Z := 12

## 關卡的靜態場景由後往前：背牆、導軌、牆面裝飾（招牌、看板）、背景道具、地形。比 LevelBackground（-100）高。
const BACK_WALL := -24
const RAILS := -23
const DECOR := -22
const PROPS := -21
const TERRAIN := -20
const SCENERY_MAX := TERRAIN

## 過場舞台：背景各層在所有演員零件之下，前景各層在其上（效果層 CutscenePlayer.EFFECT_Z 更高）。
const STAGE_BACK := -100
const STAGE_FRONT := 100
