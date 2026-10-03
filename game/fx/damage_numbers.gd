class_name DamageNumbers
extends Node2D
## 傷害數字（NE-148）：預設關閉（設定頁可開）；只顯示弱點、重擊與被擋，一般命中不顯示（準星的命中標記已經夠了）。
## 固定容量的池（陣列重複使用，不為每個數字建立節點）；同一個目標在合併時間內的數字累加成一個，不會刷屏。
## 自己用 draw_string 畫在關卡特效層，所以沒有每影格配置。

const CAPACITY := 24
const LIFETIME := 0.7
const MERGE_TIME := 0.25
const RISE_SPEED := 38.0
const SHOWN_KINDS: PackedStringArray = ["weak", "crit", "blocked"]
const COLORS := {&"weak": Color(1.0, 0.82, 0.3), &"crit": Color(1.0, 0.45, 0.35), &"blocked": Color(0.7, 0.78, 0.9)}

var _pos := PackedVector2Array()
var _age := PackedFloat32Array()
var _value := PackedInt32Array()
var _target := PackedInt64Array()
var _kind: Array[StringName] = []
var _since_merge := PackedFloat32Array()
var _alive := 0
var shown_count := 0
var merged_count := 0


func _ready() -> void:
	z_index = 8
	_pos.resize(CAPACITY)
	_age.resize(CAPACITY)
	_value.resize(CAPACITY)
	_target.resize(CAPACITY)
	_since_merge.resize(CAPACITY)
	_kind.resize(CAPACITY)
	for i in CAPACITY:
		_age[i] = LIFETIME
		_kind[i] = &""
	EventBus.damage_number.connect(show_number)


func alive_count() -> int:
	return _alive


## 顯示一個數字；關閉設定、不在顯示種類內、或沒有關卡時什麼都不做。target_id 用來合併同一目標的連續數字。
func show_number(at: Vector2, amount: int, kind: StringName, target_id: int = 0) -> void:
	if not Settings.get_damage_numbers() or not SHOWN_KINDS.has(String(kind)) or amount <= 0 and kind != &"blocked":
		return
	for i in CAPACITY:
		if _age[i] < MERGE_TIME and _target[i] == target_id and target_id != 0 and _kind[i] == kind and _age[i] < LIFETIME:
			_value[i] += amount
			_age[i] = minf(_age[i], 0.05)
			_pos[i] = at
			merged_count += 1
			return
	var slot := _free_slot()
	_pos[slot] = at
	_age[slot] = 0.0
	_value[slot] = amount
	_target[slot] = target_id
	_kind[slot] = kind
	shown_count += 1


func _free_slot() -> int:
	var oldest := 0
	for i in CAPACITY:
		if _age[i] >= LIFETIME:
			return i
		if _age[i] > _age[oldest]:
			oldest = i
	return oldest


func _process(delta: float) -> void:
	var alive := 0
	for i in CAPACITY:
		if _age[i] < LIFETIME:
			_age[i] += delta
			alive += 1
	_alive = alive
	if alive > 0 or _alive != alive:
		queue_redraw()


func _draw() -> void:
	var font := UiKit.font()
	for i in CAPACITY:
		if _age[i] >= LIFETIME:
			continue
		var t := _age[i] / LIFETIME
		var color: Color = COLORS.get(_kind[i], Color.WHITE)
		color.a = 1.0 - t * t
		var text := "擋" if _kind[i] == &"blocked" else str(_value[i])
		var size := 11 if _kind[i] != &"blocked" else 9
		var p := _pos[i] + Vector2(-4.0, -RISE_SPEED * t)
		draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.7))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
