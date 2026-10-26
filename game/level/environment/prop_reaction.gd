class_name PropReaction
extends Node2D
## 擺設依劇情旗標改變樣子（NE-240）：狀態燈換色、吐出一張紙。掛在 PropNode 底下，
## 由關卡地圖的道具項目用 "react": "<id>" 指定，內容寫在 data/environment/prop_reactions.json：
##   lamp：{at（在擺設圖上的比例位置）、radius、light_radius、light_energy、light_at、states[{flag, color, pulse}]}，
##         states 由前往後看，旗標成立的最後一個勝出；第一個不寫 flag，是預設狀態。
##   paper：{at、width、length、feed_seconds、show_flag、hide_flag}，show_flag 成立後紙從出紙口慢慢送出來，
##         hide_flag 成立（被拿走）就不見。
##   swap：{flag、prop、pack、align、offset}，flag 成立時整件擺設換成另一件（收起的梯子換成放下的、關著的配電盤換成打開的）。
##         prop 是另一件擺設的 id、pack 是它所在的資料夾；align＝"bottom"（預設，兩件都站在同一條底邊）或 "top"（掛在同一個高度往下延伸）。
##         兩件預設靠左對齊；offset＝[x, y] 再位移幾個世界像素（打開的門板往左多出一塊時，把箱體對回原位）。
##   dial：{at、length、from_deg、to_deg、flag、turn_seconds、color}，一根開度指針；flag 成立時從 from_deg 慢慢轉到 to_deg
##         （0 度朝右、90 度朝下），看得出閥門轉過了，不只靠燈的顏色。
## 進關卡時旗標已經成立＝直接是結果的樣子，不重播送紙與聲音；玩家在場時旗標才成立，才播一次。
## 這裡只管畫面與聲音，不寫旗標、不發物品。資料缺漏時記錄是哪一筆並略過那一項，擺設照常顯示。

const TABLE_PATH := "res://data/environment/prop_reactions.json"
## 紙送出來時每秒喀幾下（出紙機構的聲音）；最多同時只響這一個。
const FEED_TICK_SECONDS := 0.16

static var _table: Dictionary = {}
static var _table_loaded := false

var _size := Vector2.ZERO
var _lamp: Dictionary = {}
var _lamp_at := Vector2.ZERO
var _lamp_flip := false
var _lamp_state: Dictionary = {}
var _light: PointLight2D
var _paper: Dictionary = {}
var _paper_at := Vector2.ZERO
var _paper_shown := false
var _paper_progress := 0.0
var _paper_visual: PropPaperVisual
var _paper_carrier: WeakRef
var _contacts: Dictionary[StringName, Vector2] = {}
var reaction_id: StringName
var _tick_left := 0.0
var _time := 0.0
var _dial: Dictionary = {}
var _dial_at := Vector2.ZERO
var _dial_flip := false
var _dial_on := false
var _dial_progress := 0.0
var _swap: Dictionary = {}
var _swap_data: PropData
var _swap_node: PropNode
var _swap_flip := false
var _swapped := false
var _swap_hidden: Array[CanvasItem] = []


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
	self.reaction_id = StringName(reaction_id)
	var contacts: Variant = spec.get("contacts", {})
	if contacts is Dictionary and contacts.size() <= 8:
		for key: Variant in contacts:
			var point: Variant = contacts[key]
			if key is String and key.is_valid_identifier() and point is Array and point.size() == 2 \
					and typeof(point[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(point[1]) in [TYPE_INT, TYPE_FLOAT] \
					and is_finite(float(point[0])) and is_finite(float(point[1])) \
					and float(point[0]) >= 0.0 and float(point[0]) <= 1.0 and float(point[1]) >= 0.0 and float(point[1]) <= 1.0:
				_contacts[StringName(key)] = _place(point, flip)
			else:
				push_warning("[PropReaction] %s contact %s is invalid; ignored" % [reaction_id, key])
	LightKit.mark_emissive(self)
	if spec.get("lamp") is Dictionary:
		_lamp = spec["lamp"]
		_lamp_at = _place(_lamp.get("at"), flip)
		_lamp_flip = flip
		if not _lamp.get("states") is Array or (_lamp["states"] as Array).is_empty():
			push_error("[PropReaction] %s 的 lamp 沒有 states，略過狀態燈" % reaction_id)
			_lamp = {}
	if spec.get("paper") is Dictionary:
		_paper = spec["paper"]
		_paper_at = _place(_paper.get("at"), flip)
		if str(_paper.get("show_flag", "")).is_empty():
			push_error("[PropReaction] %s 的 paper 沒有 show_flag，略過出紙" % reaction_id)
			_paper = {}
		else:
			for key: String in ["width", "length", "feed_seconds"]:
				var value: Variant = _paper.get(key, 1.0)
				var limit := 32.0 if key != "feed_seconds" else 10.0
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0 or float(value) > limit:
					push_warning("[PropReaction] %s paper.%s is invalid; paper disabled" % [reaction_id, key])
					_paper = {}
					break
	if spec.get("dial") is Dictionary:
		_dial = spec["dial"]
		_dial_at = _place(_dial.get("at"), flip)
		_dial_flip = flip
		if str(_dial.get("flag", "")).is_empty():
			push_error("[PropReaction] %s 的 dial 沒有 flag，略過指針" % reaction_id)
			_dial = {}
	if spec.get("swap") is Dictionary:
		_swap = spec["swap"]
		_swap_flip = flip
		var pack := str(_swap.get("pack", PropLibrary.DEFAULT_DIR))
		_swap_data = PropLibrary.find(StringName(str(_swap.get("prop", ""))), pack) if not str(_swap.get("flag", "")).is_empty() else null
		if _swap_data == null:
			push_error("[PropReaction] %s 的 swap 要有 flag，而且 prop（%s）要在 %s 裡；略過換樣子" % [reaction_id, _swap.get("prop", ""), pack])
			_swap = {}


func _ready() -> void:
	if not _paper.is_empty():
		_paper_visual = PropPaperVisual.new()
		_paper_visual.name = "ReceiptPaper"
		_paper_visual.width = clampf(float(_paper.get("width", 4.0)), 1.0, 16.0)
		_paper_visual.length = clampf(float(_paper.get("length", 8.0)), 1.0, 32.0)
		_paper_visual.position = _paper_at
		LightKit.mark_emissive(_paper_visual)
		add_child(_paper_visual)
	if not _lamp.is_empty() and float(_lamp.get("light_radius", 0.0)) > 0.0:
		_light = LightKit.create_point_light(Color.WHITE, float(_lamp["light_radius"]), float(_lamp.get("light_energy", 0.6)))
		# 光預設從燈的位置出發；light_at 可以改成擺設的中間，讓狀態燈的顏色照在整件擺設上。
		_light.position = _place(_lamp["light_at"], _lamp_flip) if _lamp.has("light_at") else _lamp_at
		add_child(_light)
	if not _swap.is_empty():
		_swap_node = PropNode.new()
		var top := 0.0 if str(_swap.get("align", "bottom")) == "top" else _size.y - _swap_data.size.y
		var offset := _offset(_swap.get("offset"))
		# 鏡像時另一件也從右邊對齊，位移跟著反過來。
		var left := (_size.x - _swap_data.size.x - offset.x) if _swap_flip else offset.x
		_swap_node.setup(_swap_data, Vector2(left, top + offset.y), _swap_flip)
		_swap_node.visible = false
		# 換上的那一件畫在狀態燈與指針後面，燈號換了樣子之後還看得到。
		_swap_node.show_behind_parent = true
		add_child(_swap_node)
	GameState.flag_changed.connect(_on_flag_changed)
	_refresh(false)


func _exit_tree() -> void:
	if is_instance_valid(_paper_visual) and _paper_visual.get_parent() != self:
		_paper_visual.queue_free()
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
	if not _dial.is_empty():
		_dial_on = GameState.has_flag(StringName(str(_dial["flag"])))
		if not live:
			_dial_progress = 1.0 if _dial_on else 0.0
	if _swap_node != null:
		var on := GameState.has_flag(StringName(str(_swap["flag"])))
		if on != _swapped:
			_swapped = on
			if on:
				# 原本那一件的圖、發光與光源整組藏起來，換上另一件；只記下自己藏掉的，換回來時不動本來就隱藏的。
				_swap_hidden.clear()
				for sibling in get_parent().get_children():
					if sibling != self and sibling is CanvasItem and (sibling as CanvasItem).visible:
						(sibling as CanvasItem).visible = false
						_swap_hidden.append(sibling)
			else:
				for item in _swap_hidden:
					if is_instance_valid(item):
						item.visible = true
				_swap_hidden.clear()
			_swap_node.visible = on
	set_process(_needs_process())
	_sync_paper()
	queue_redraw()


## 目前是不是換成另一件了（測試與工具用）。
func is_swapped() -> bool:
	return _swapped


func _needs_process() -> bool:
	return float(_lamp_state.get("pulse", 0.0)) > 0.0 or (_paper_shown and _paper_progress < 1.0) or _dial_turning()


func _dial_turning() -> bool:
	return not _dial.is_empty() and not is_equal_approx(_dial_progress, 1.0 if _dial_on else 0.0)


## 指針轉到哪了（0＝還沒轉、1＝轉到底；測試與工具用）。
func dial_progress() -> float:
	return _dial_progress


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
	if _dial_turning():
		_dial_progress = move_toward(_dial_progress, 1.0 if _dial_on else 0.0, delta / maxf(0.1, float(_dial.get("turn_seconds", 1.2))))
		if not _dial_turning():
			Sfx.play(&"switch", -14.0)
			set_process(_needs_process())
	_sync_paper()
	queue_redraw()


## Only this fixture's presentation clock may advance while gameplay is paused.
func presentation_tick(delta: float) -> void:
	if is_inside_tree() and get_tree().paused and is_finite(delta) and delta > 0.0:
		_process(minf(delta, 0.1))


func paper_tip_global() -> Vector2:
	return _paper_visual.to_global(Vector2(0.0, _paper_visual.length * _paper_progress)) if is_instance_valid(_paper_visual) and _paper_shown else Vector2.INF


func contact_global(id: StringName) -> Vector2:
	return to_global(_contacts[id]) if _contacts.has(id) else Vector2.INF


func paper_ready() -> bool:
	return _paper_shown and _paper_progress >= 1.0 and is_instance_valid(_paper_visual) and _paper_carrier == null


func claim_paper(carrier: Node2D) -> PropPaperVisual:
	if not paper_ready() or not is_instance_valid(carrier) or not carrier.is_inside_tree():
		return null
	_paper_carrier = weakref(carrier)
	_paper_visual.reparent(carrier, true)
	return _paper_visual


func return_paper(carrier: Node2D) -> void:
	if _paper_carrier == null or _paper_carrier.get_ref() != carrier:
		return
	_paper_carrier = null
	if is_instance_valid(_paper_visual):
		_paper_visual.reparent(self, false)
		_paper_visual.transform = Transform2D.IDENTITY
		_paper_visual.position = _paper_at
	_sync_paper()


func _sync_paper() -> void:
	if not is_instance_valid(_paper_visual):
		return
	_paper_visual.progress = _paper_progress
	if _paper_carrier == null:
		_paper_visual.visible = _paper_shown
	elif not _paper_shown:
		_paper_visual.hide()
	_paper_visual.queue_redraw()


func _lamp_color() -> Color:
	return Color.from_string(str(_lamp_state.get("color", "#ffffff")), Color.WHITE)


func _draw() -> void:
	if not _dial.is_empty():
		_draw_dial()
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


## 開度指針：深色底線加一條亮線，樞紐一個小圓點；轉動用緩入緩出。
func _draw_dial() -> void:
	var degrees := lerpf(float(_dial.get("from_deg", 0.0)), float(_dial.get("to_deg", 90.0)), smoothstep(0.0, 1.0, _dial_progress))
	if _dial_flip:
		degrees = 180.0 - degrees
	var tip := _dial_at + Vector2.from_angle(deg_to_rad(degrees)) * float(_dial.get("length", 5.0))
	var color := Color.from_string(str(_dial.get("color", "#f2e8c8")), Color.WHITE)
	draw_line(_dial_at, tip, Color(0.05, 0.06, 0.09), 1.8)
	draw_line(_dial_at, tip, color, 0.9)
	draw_circle(_dial_at, 1.1, Color(0.05, 0.06, 0.09))
	draw_circle(_dial_at, 0.6, color)


func _place(value: Variant, flip: bool) -> Vector2:
	var at := Vector2(0.5, 0.5)
	if value is Array and value.size() == 2:
		at = Vector2(float(value[0]), float(value[1]))
	if flip:
		at.x = 1.0 - at.x
	return at * _size


## 世界像素的位移；不是兩個數字就當成不位移。
static func _offset(value: Variant) -> Vector2:
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


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
