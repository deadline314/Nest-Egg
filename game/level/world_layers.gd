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
## 關卡角色從 CHARACTERS_BOTTOM 起排，所以 ENTITY_BEHIND 到 CHARACTERS_BOTTOM 之間的實體圖層都在所有角色之下。
const ENTITY_BEHIND := CHARACTER_MIN_Z - 1

## 關卡裡的角色（玩家、敵人、場景人物）：這些節點自己管理零件的圖層，不套用 ENTITY_BEHIND。
static func is_character(node: Node) -> bool:
	return node is Player or node is Enemy or node is NpcActor


## 關卡裡每個角色佔一整組圖層（NE-402），組與組不交錯：重疊時一定是整個角色在另一個前面。
## 敵人與場景人物依出現順序拿最低的空組（後出現的在前面），活著的期間不換組；玩家固定在最上面一組。
## 第 n 組的根節點 z 是 (n + 1) × CHARACTER_SPAN，最低的零件（−9）仍高於 ENTITY_BEHIND 與所有「角色之下」的實體。
## 同時在場的角色超過組數時共用最後一組並記錄（Level 會寫出是哪個區域）。
const LEVEL_ACTOR_SLOTS := 48
const PLAYER_Z := (LEVEL_ACTOR_SLOTS + 1) * CHARACTER_SPAN
## 所有關卡角色零件的範圍：最低一組的最低零件、玩家的最高零件。
const CHARACTERS_BOTTOM := CHARACTER_SPAN + CHARACTER_MIN_Z
const CHARACTERS_TOP := PLAYER_Z + CHARACTER_MAX_Z

## 畫在所有角色之上的東西，由後往前。
## 跟著角色的提示線、頭頂標記；水坑的水面（淹過角色）。
const ABOVE_CHARACTERS := CHARACTERS_TOP + 1
const PROJECTILES := CHARACTERS_TOP + 4
## 會擋子彈的蒸汽幕：子彈消失在蒸汽裡要看得到。
const STEAM_SCREEN := PROJECTILES + 1
const FX := CHARACTERS_TOP + 6
const FOG := CHARACTERS_TOP + 7
const RAIN := CHARACTERS_TOP + 8
## 前景擺設（不透明）：在霧與雨之前，代表比走道更靠近鏡頭。
const FRONT_PROPS := CHARACTERS_TOP + 10
const FOREGROUND := CHARACTERS_TOP + 15
const WORLD_PROMPTS := CHARACTERS_TOP + 20
const MAP_BUBBLES := CHARACTERS_TOP + 30
## 世界裡最上面的圖層；光源的 z 範圍要涵蓋到這裡（LightKit）。
const WORLD_TOP := MAP_BUBBLES


## 關卡裡第 slot 組角色的根節點 z（slot 超出上限時夾在最後一組）。
static func level_actor_z(slot: int) -> int:
	return (clampi(slot, 0, LEVEL_ACTOR_SLOTS - 1) + 1) * CHARACTER_SPAN


## 檢查與截圖用：root 底下所有看得到、跟著 root 圖層的節點實際畫在哪個 z（相對 z 沿祖先加總到 root，含 root 自己）。
## 不跟著 root 的（絕對 z、top_level，例如提示框、接觸陰影）不算。沒有任何節點時回傳 (0, -1)。
static func drawn_z_range(root: CanvasItem) -> Vector2i:
	var low := 1 << 30
	var high := -(1 << 30)
	for node: Node in root.find_children("*", "CanvasItem", true, false):
		var z: Variant = _z_within(node as CanvasItem, root)
		if z != null:
			low = mini(low, z)
			high = maxi(high, z)
	return Vector2i(low, high) if low <= high else Vector2i(0, -1)


## item 跟著 root 的圖層時回傳它實際的 z，否則回傳 null（隱藏、絕對 z、top_level、中間隔著非 CanvasItem）。
static func _z_within(item: CanvasItem, root: CanvasItem) -> Variant:
	var z := root.z_index
	var node: Node = item
	while node != root:
		var canvas := node as CanvasItem
		if canvas == null or not canvas.visible or not canvas.z_as_relative or canvas.top_level:
			return null
		z += canvas.z_index
		node = node.get_parent()
	return z


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
