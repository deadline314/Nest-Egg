class_name WorldLayers
extends RefCounted
## 圖層順序（z_index）：靜態場景一律畫在所有角色零件之下。
## 角色骨架的零件有自己的 z（art/characters/*/character.json），最低到 -9（後側的手、腳、頭髮），最高到 +12（外層裝甲、武器）；
## 背景若排在 -9 以上，後側的手腳就會被背牆、地形、裝飾蓋住（看起來只有一隻腳）。新增靜態場景圖層請排在 SCENERY_MAX 以下。

## 角色零件的 z 範圍（資料檢查用：測試會確認真實資料沒有超出）。
const CHARACTER_MIN_Z := -9
const CHARACTER_MAX_Z := 12

## 一個角色佔的 z 範圍（含兩端）。同時出現、可能重疊的角色（過場演員）要錯開至少這麼多，零件才不會互相穿插
## （例如一個角色的衣服一半在另一個角色後面、一半在前面）。
const CHARACTER_SPAN := CHARACTER_MAX_Z - CHARACTER_MIN_Z + 1

## 關卡裡不是角色的東西（看板、檢查點、出入口、開關、拾取物、箱子…）一律排在所有角色零件之下、靜態場景之上，
## 角色走過時不會出現「後腳在看板後面、前腳在看板前面」。已經有自己圖層的（前景道具、水面）不動。
const ENTITY_BEHIND := CHARACTER_MIN_Z - 1

## 關卡裡的角色（玩家、敵人、場景人物）：這些節點自己管理零件的圖層，不套用 ENTITY_BEHIND。
static func is_character(node: Node) -> bool:
	return node is Player or node is Enemy or node is NpcActor


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
## 過場舞台同時可以有幾個演員各佔一組圖層（再多就共用最後一組，並記錄警告）：第 n 個演員的 z 起點是 n × CHARACTER_SPAN，
## 最前面一組的最高零件要低於 STAGE_FRONT。
@warning_ignore("integer_division")
const MAX_STAGE_ACTORS := (STAGE_FRONT - 1 - CHARACTER_MAX_Z) / CHARACTER_SPAN + 1


## 過場舞台第 slot 個演員的 z 起點（slot 超出上限時夾在最後一組）。
static func stage_actor_z(slot: int) -> int:
	return clampi(slot, 0, MAX_STAGE_ACTORS - 1) * CHARACTER_SPAN
