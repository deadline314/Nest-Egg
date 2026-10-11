class_name PropReaction
extends Node2D
## 擺設依劇情旗標改變樣子（NE-240）：狀態燈換色、吐出一張紙。掛在 PropNode 底下，
## 由關卡地圖的道具項目用 "react": "<id>" 指定，內容寫在 data/environment/prop_reactions.json：
##   lamp：{at（在擺設圖上的比例位置）、radius、light_radius、states[{flag, color, pulse}]}，
##         states 由前往後看，旗標成立的最後一個勝出；第一個不寫 flag，是預設狀態。
##   paper：{at、width、length、feed_seconds、show_flag、hide_flag}，show_flag 成立後紙從出紙口慢慢送出來，
##         hide_flag 成立（被拿走）就不見。
## 進關卡時旗標已經成立＝直接是結果的樣子，不重播送紙與聲音；玩家在場時旗標才成立，才播一次。
## 這裡只管畫面與聲音，不寫旗標、不發物品。資料缺漏時記錄是哪一筆並略過那一項，擺設照常顯示。

const TABLE_PATH := "res://data/environment/prop_reactions.json"
const PAPER_COLOR := Color(0.93, 0.9, 0.8)
const PAPER_INK := Color(0.36, 0.38, 0.44)
## 紙送出來時每秒喀幾下（出紙機構的聲音）；最多同時只響這一個。
const FEED_TICK_SECONDS := 0.16

static var _table: Dictionary = {}
static var _table_loaded := false

var _size := Vector2.ZERO
var _lamp: Dictionary = {}
var _lamp_at := Vector2.ZERO
var _lamp_state: Dictionary = {}
var _light: PointLight2D
var _paper: Dictionary = {}
var _paper_at := Vector2.ZERO
var _paper_shown := false
var _paper_progress := 0.0
var _tick_left := 0.0
var _time := 0.0


## 依 id 建立反應並掛在 prop 底下；id 不存在回傳 null 並記錄。flip＝擺設左右鏡像時位置跟著鏡像。
static func attach(prop: Node2D, reaction_id: String, prop_size: Vector2, flip := false) -> PropReaction:
	var spec := _spec(reaction_id)
	if spec.is_empty():
		push_error("[PropReaction] %s 沒有 %s 這個反應，擺設維持原樣" % [TABLE_PATH, reaction_id])
		return null
	var node := PropReaction.new()
	node.name = "Reaction_" + reaction_id
	node._size = prop_size
	node._setup(spec, flip, reaction_id)
	prop.add_child(node)
	return node


func _setup(spec: Dictionary, flip: bool, reaction_id: String) -> void:
	LightKit.mark_emissive(self)
	if spec.get("lamp") is Dictionary:
		_lamp = spec["lamp"]
		_lamp_at = _place(_lamp.get("at"), flip)
		if not _lamp.get("states") is Array or (_lamp["states"] as Array).is_empty():
			push_error("[PropReaction] %s 的 lamp 沒有 states，略過狀態燈" % reaction_id)
			_lamp = {}
	if spec.get("paper") is Dictionary:
		_paper = spec["paper"]
		_paper_at = _place(_paper.get("at"), flip)
		if str(_paper.get("show_flag", "")).is_empty():
			push_error("[PropReaction] %s 的 paper 沒有 show_flag，略過出紙" % reaction_id)
			_paper = {}


func _ready() -> void:
	if not _lamp.is_empty() and float(_lamp.get("light_radius", 0.0)) > 0.0:
		_light = LightKit.create_point_light(Color.WHITE, float(_lamp["light_radius"]), float(_lamp.get("light_energy", 0.6)))
		_light.position = _lamp_at
		add_child(_light)
	GameState.flag_changed.connect(_on_flag_changed)
	_refresh(false)


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)


func _on_flag_changed(_flag: StringName, _value: Variant) -> void:
	_refresh(true)


## live＝玩家在場時旗標改變（要演出來）；false＝進關卡時依現況直接擺好。
func _refresh(live: bool) -> void:
	if not _lamp.is_empty():
		for state: Variant in _lamp["states"]:
			if state is Dictionary and (str(state.get("flag", "")).is_empty() or GameState.has_flag(StringName(str(state["flag"])))):
				_lamp_state = state
		if _light != null:
			_light.color = _lamp_color()
	if not _paper.is_empty():
		var hide_flag := str(_paper.get("hide_flag", ""))
		var shown := GameState.has_flag(StringName(str(_paper["show_flag"]))) and (hide_flag.is_empty() or not GameState.has_flag(StringName(hide_flag)))
		if shown and not _paper_shown:
			_paper_progress = 0.0 if live else 1.0
			_tick_left = 0.0
		_paper_shown = shown
	set_process(_needs_process())
	queue_redraw()


func _needs_process() -> bool:
	return float(_lamp_state.get("pulse", 0.0)) > 0.0 or (_paper_shown and _paper_progress < 1.0)


func _process(delta: float) -> void:
	_time += delta
	if _paper_shown and _paper_progress < 1.0:
		_paper_progress = minf(1.0, _paper_progress + delta / maxf(0.1, float(_paper.get("feed_seconds", 1.0))))
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = FEED_TICK_SECONDS
			Sfx.play(&"switch", -16.0)
		if _paper_progress >= 1.0:
			Sfx.play(&"beep", -14.0)
			set_process(_needs_process())
	queue_redraw()


func _lamp_color() -> Color:
	return Color.from_string(str(_lamp_state.get("color", "#ffffff")), Color.WHITE)


func _draw() -> void:
	if _paper_shown:
		_draw_paper()
	if not _lamp_state.is_empty():
		var color := _lamp_color()
		var radius := float(_lamp.get("radius", 1.4))
		var pulse_seconds := float(_lamp_state.get("pulse", 0.0))
		# 緩慢起伏（一個來回 pulse 秒），不是閃爍。
		var level := 0.5 + 0.5 * sin(_time * TAU / pulse_seconds) if pulse_seconds > 0.0 else 1.0
		draw_circle(_lamp_at, radius * (2.0 + 0.6 * level), Color(LightKit.glow(color, 1.0), 0.16 + 0.14 * level))
		draw_circle(_lamp_at, radius, LightKit.glow(color, 1.3 + 0.5 * level))
		if _light != null:
			_light.energy = float(_lamp.get("light_energy", 0.6)) * (0.7 + 0.3 * level)


## 一張從出紙口往下送出來的回執：米色紙、幾行印字、鋸齒狀的撕口。紙不是發光體，用暗一點的顏色畫。
func _draw_paper() -> void:
	var width := float(_paper.get("width", 4.0))
	var length := float(_paper.get("length", 8.0)) * _paper_progress
	if length < 0.5:
		return
	var left := _paper_at.x - width * 0.5
	var top := _paper_at.y
	var shade := 0.8
	draw_rect(Rect2(left, top, width, length), Color(PAPER_COLOR.r * shade, PAPER_COLOR.g * shade, PAPER_COLOR.b * shade))
	var line := top + 1.5
	while line < top + length - 1.2:
		draw_line(Vector2(left + 0.7, line), Vector2(left + width - 0.7, line), Color(PAPER_INK, 0.8), 0.5)
		line += 1.6
	# 撕口：底邊三個小齒。
	var tooth := width / 3.0
	for i in 3:
		var x := left + tooth * i
		draw_colored_polygon(PackedVector2Array([Vector2(x, top + length), Vector2(x + tooth, top + length), Vector2(x + tooth * 0.5, top + length + 0.9)]),
				Color(PAPER_COLOR.r * shade, PAPER_COLOR.g * shade, PAPER_COLOR.b * shade))


func _place(value: Variant, flip: bool) -> Vector2:
	var at := Vector2(0.5, 0.5)
	if value is Array and value.size() == 2:
		at = Vector2(float(value[0]), float(value[1]))
	if flip:
		at.x = 1.0 - at.x
	return at * _size


static func _spec(reaction_id: String) -> Dictionary:
	if not _table_loaded:
		_table_loaded = true
		if FileAccess.file_exists(TABLE_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
			if parsed is Dictionary:
				_table = parsed
			else:
				push_error("[PropReaction] %s 不是有效的 JSON 物件" % TABLE_PATH)
		else:
			push_error("[PropReaction] 找不到 %s" % TABLE_PATH)
	var spec: Variant = _table.get(reaction_id)
	return spec if spec is Dictionary else {}


## 測試用：清掉讀過的資料，下次重新讀檔。
static func clear_cache() -> void:
	_table = {}
	_table_loaded = false
