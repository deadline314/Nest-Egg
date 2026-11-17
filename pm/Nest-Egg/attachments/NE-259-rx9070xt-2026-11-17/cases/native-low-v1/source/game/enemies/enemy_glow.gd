class_name EnemyGlow
extends Node2D
## 敵人自帶的光（NE-259）：看門狗的眼睛、重裝兵面罩的橫條燈這類「有道理帶燈」的敵人。
## 光的位置、顏色、大小與發光標記都寫在敵人資料（EnemyData 的 Light 群組）；新增一種帶燈的敵人只要填資料，
## 不用改敵人的零件、貼圖與骨架。資料裡半徑是 0 的敵人不會建立這個元件（清掃兵、收帳人等一般敵人不帶燈）。
##
## 光跟著指定的零件走（骨架角色的骨頭、零件式生物的零件；找不到就用相對於腳底的位置並記錄一次）。
## 光色表示狀態：平常是它自己的顏色；發現主角時變亮；準備攻擊時轉成全遊戲共用的紅色預兆；死亡時在死亡演出內熄滅。
## 光登記在場景光源裡，由光源預算管理（同時亮著的燈數有上限），也會讓附近的角色在牆上投影。

## 發現主角、準備攻擊時亮度是平常的幾倍。
const ALERT_GAIN := 1.7
const TELEGRAPH_GAIN := 2.1
## 顏色與亮度追上目標的速度（每秒）：狀態改變是漸變，不是一格跳過去。
const BLEND := 9.0
## 死亡後多快熄滅（每秒降低的亮度比例）。
const DEATH_FADE := 3.5
## 發光標記（眼睛、面罩燈條）的亮度。
const MARK_GLOW := 1.5

var _enemy: Enemy
var _light: PointLight2D
var _anchor: Node2D
var _searched := false
var _level := 1.0
var _color := Color.WHITE
var _mark := Vector2.ZERO
var _fsm_state: StringName = &""
var _engaged := false


## 替 enemy 掛上自帶的光；資料沒有設定光（半徑 0）回傳 null。
static func attach(enemy: Enemy) -> EnemyGlow:
	if enemy == null or enemy.data == null or enemy.data.light_radius <= 0.0:
		return null
	var glow := EnemyGlow.new()
	glow.name = "EnemyGlow"
	glow._enemy = enemy
	enemy.add_child(glow)
	return glow


func _ready() -> void:
	var data := _enemy.data
	_color = data.light_color
	_mark = data.light_mark
	material = LightKit.emissive_material()
	z_index = 1
	_light = LightKit.create_point_light(_color, data.light_radius, data.light_energy)
	add_child(_light)
	_place()


## 目前的狀態：calm 平常、alert 發現主角、telegraph 準備攻擊、dying 死亡中（測試與量測用）。
func state() -> StringName:
	if _enemy.is_dying():
		return &"dying"
	if _enemy.is_telegraphing():
		return &"telegraph"
	if _enemy.is_alerted() or _is_engaged():
		return &"alert"
	return &"calm"


## 敵人是不是已經發現主角：狀態不在資料列的平靜狀態裡就算（light_calm_states；沒填就用 relaxed_states：巡邏、待機…）。
## 只在狀態改變時重查。
func _is_engaged() -> bool:
	var current: StringName = _enemy.fsm.current
	if current != _fsm_state:
		_fsm_state = current
		var calm := _enemy.data.light_calm_states if not _enemy.data.light_calm_states.is_empty() else _enemy.data.relaxed_states
		_engaged = current != &"" and not calm.has(String(current))
	return _engaged


## 現在的亮度比例（平常＝1；死亡後降到 0）。
func level() -> float:
	return _level


func light() -> PointLight2D:
	return _light


func _process(delta: float) -> void:
	_place()
	var target_color := _enemy.data.light_color
	var target_level := 1.0
	match state():
		&"dying":
			_level = move_toward(_level, 0.0, delta * DEATH_FADE * maxf(_level, 0.3))
			target_level = _level
		&"telegraph":
			target_color = Palette.DANGER
			target_level = TELEGRAPH_GAIN
		&"alert":
			target_level = ALERT_GAIN
	if not _enemy.is_dying():
		_level = lerpf(_level, target_level, 1.0 - exp(-BLEND * delta))
	var blended := _color.lerp(target_color, 1.0 - exp(-BLEND * delta))
	if not blended.is_equal_approx(_color) or not is_equal_approx(_light.energy, _enemy.data.light_energy * _level):
		_color = blended
		_light.color = _color
		_light.energy = _enemy.data.light_energy * _level
		_light.enabled = _level > 0.01
		if _mark != Vector2.ZERO:
			queue_redraw()


## 跟著指定的零件：骨架角色用骨頭，零件式生物用零件的關節；面向左邊時位置跟著翻。
func _place() -> void:
	var data := _enemy.data
	if not _searched:
		_searched = true
		_anchor = _find_anchor(data.light_part)
		if _anchor == null and data.light_part != &"":
			RigLibrary.report_once("enemy_glow:%s" % data.id, "[EnemyGlow] 敵人「%s」找不到光要跟著的零件「%s」，改用相對於腳底的位置" % [data.id, data.light_part])
	var offset := Vector2(data.light_offset.x * float(_enemy.facing), data.light_offset.y)
	if _anchor != null and is_instance_valid(_anchor):
		global_position = _anchor.global_position + offset
	else:
		position = offset


func _find_anchor(part: StringName) -> Node2D:
	if part == &"":
		return null
	if _enemy.rig != null:
		return _enemy.rig.bone(part)
	if _enemy.creature != null:
		return _enemy.creature.find_child(String(part), true, false) as Node2D
	return null


## 發光標記：一小條亮的（眼睛、面罩燈條），顏色與亮度跟著狀態，光才看得到是從哪裡來的。
func _draw() -> void:
	if _mark == Vector2.ZERO or _level <= 0.01:
		return
	draw_rect(Rect2(-_mark * 0.5, _mark), LightKit.glow(_color, MARK_GLOW * minf(_level, 1.6)))
