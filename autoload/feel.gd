extends Node
## 打擊回饋的單一入口（NE-131）：頓幀、鏡頭震動都從這裡播放，數值放在 data/feel/events.json。
## 固定的回饋用 Feel.play(&"事件名", ctx)；數值隨武器或特效資料而定的用 Feel.shake / Feel.freeze / Feel.hitstop。
## ctx 可帶：targets（局部頓幀要凍結的節點）、freeze（覆寫凍結秒數）、scale（整體倍率）。
## 資料缺漏或損毀時記錄「檔案、事件、欄位」並略過該項，不會崩潰。

const PATH := "res://data/feel/events.json"
## 舊的震動「強度」換成像素的係數（強度 1 = 0.8 px）。
const STRENGTH_TO_PX := 0.8
const MAX_SHAKE_PX := 12.0
const KNOWN_FIELDS: PackedStringArray = ["shake", "hitstop", "freeze", "slowmo", "zoom", "screen"]
## 縮放脈衝只允許這些事件（重要時刻），避免畫面一直在縮放。
const ZOOM_WHITELIST: PackedStringArray = ["player_parry", "player_finisher", "boss_death", "boss_phase_shift"]

## 各系統回報的計數（實驗室診斷用）：名稱 → 次數。
var counters: Dictionary = {}
## 最近播放的回饋、聲音與材質事件（實驗室的事件時間軸）：「秒數 種類 名稱」。
var recent: PackedStringArray = []
const RECENT_MAX := 10
## 目前的手感預設組合（data/feel/presets.json）：對震動、頓幀、縮放脈衝的整體倍率；玩家設定再乘在上面。
var preset: StringName = &"standard"
var _events: Dictionary = {}
var _gauges: Dictionary = {}
var _reported: Dictionary = {}


func _ready() -> void:
	reload()
	register_counter("hitstop_budget_left", Fx.hitstop_budget_left)
	register_counter("particles", Fx.particle_count)
	register_counter("fps", func() -> int: return int(Engine.get_frames_per_second()))
	register_counter("frame_ms", func() -> float: return snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1))
	register_counter("flash_per_second", func() -> int: return FlashGuard.rate())
	register_counter("flash_peak", func() -> float: return snappedf(FlashGuard.peak, 0.01))
	register_counter("flash_dropped", func() -> int: return FlashGuard.dropped)
	register_counter("voices_playing", Sfx.voices_playing)
	register_counter("sounds_dropped", func() -> int: return Sfx.dropped_count)
	register_counter("frozen_nodes", Fx.frozen_count)
	register_counter("slowmo_active", func() -> int: return int(Fx.is_slowmo()))


func reload() -> void:
	_events = {}
	var json: JSON = load(PATH) as JSON if ResourceLoader.exists(PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("events")) != TYPE_DICTIONARY:
		_report("load", "[Feel] 無法讀取回饋事件資料：%s（需要 events 字典）" % PATH)
		return
	_events = (json.data as Dictionary)["events"]


## 記錄一筆事件到時間軸（各系統呼叫）。
func record(kind: String, id: String) -> void:
	recent.append("%.2f %s %s" % [Time.get_ticks_msec() * 0.001, kind, id])
	while recent.size() > RECENT_MAX:
		recent.remove_at(0)


func set_preset(id: StringName) -> bool:
	if not FeelParams.presets().has(String(id)):
		_report("preset:" + String(id), "[Feel] 沒有這個預設組合「%s」（%s）" % [id, FeelParams.PRESETS_PATH])
		return false
	preset = id
	return true


func preset_scale(category: String) -> float:
	return float((FeelParams.presets().get(String(preset), {}) as Dictionary).get(category, 1.0))


## 事件的即時資料（實驗室直接改這份，立刻影響播放）；不存在回傳空字典。
func event_def(id: StringName) -> Dictionary:
	return _events.get(String(id), {})


## 目前記憶體中全部事件（寫回資料檔用）。
func all_events() -> Dictionary:
	return _events


func has_event(id: StringName) -> bool:
	return _events.has(String(id))


func event_ids() -> Array:
	return _events.keys()


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題），供測試與實驗室使用。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for id: String in _events.keys():
		var def: Variant = _events[id]
		if typeof(def) != TYPE_DICTIONARY:
			errors.append("%s 的事件「%s」不是字典" % [PATH, id])
			continue
		for field: String in (def as Dictionary).keys():
			if not KNOWN_FIELDS.has(field):
				errors.append("%s 的事件「%s」有不認得的欄位「%s」" % [PATH, id, field])
		var shake: Variant = (def as Dictionary).get("shake")
		if shake != null:
			if typeof(shake) != TYPE_DICTIONARY or float((shake as Dictionary).get("px", 0.0)) <= 0.0 or float((shake as Dictionary).get("time", 0.0)) <= 0.0:
				errors.append("%s 的事件「%s」的 shake 要有大於 0 的 px 與 time" % [PATH, id])
		var slowmo: Variant = (def as Dictionary).get("slowmo")
		if slowmo != null:
			var s := slowmo as Dictionary if typeof(slowmo) == TYPE_DICTIONARY else {}
			if not Fx.SLOWMO_WHITELIST.has(str(s.get("reason", ""))) or float(s.get("scale", 0.0)) <= 0.0 or float(s.get("time", 0.0)) <= 0.0:
				errors.append("%s 的事件「%s」的 slowmo 要有白名單內的 reason（%s）與大於 0 的 scale、time" % [PATH, id, ", ".join(Fx.SLOWMO_WHITELIST)])
		if (def as Dictionary).has("screen") and not PostProcess.effects().has(str((def as Dictionary)["screen"])):
			errors.append("%s 的事件「%s」的 screen 引用不存在的全螢幕效果「%s」" % [PATH, id, (def as Dictionary)["screen"]])
		var zoom: Variant = (def as Dictionary).get("zoom")
		if zoom != null:
			var z := zoom as Dictionary if typeof(zoom) == TYPE_DICTIONARY else {}
			if not ZOOM_WHITELIST.has(id) or float(z.get("amount", 0.0)) <= 0.0 or float(z.get("time", 0.0)) <= 0.0:
				errors.append("%s 的事件「%s」的 zoom 只允許白名單事件（%s），且 amount、time 要大於 0" % [PATH, id, ", ".join(ZOOM_WHITELIST)])
		for field in ["hitstop", "freeze"]:
			if (def as Dictionary).has(field) and float((def as Dictionary)[field]) <= 0.0:
				errors.append("%s 的事件「%s」的 %s 要大於 0" % [PATH, id, field])
	return errors


func play(id: StringName, ctx: Dictionary = {}) -> void:
	var def: Variant = _events.get(String(id))
	if typeof(def) != TYPE_DICTIONARY:
		_report("event:" + String(id), "[Feel] 沒有這個回饋事件「%s」（%s）" % [id, PATH])
		return
	var scale := float(ctx.get("scale", 1.0))
	_count("events")
	record("回饋", String(id))
	var shake: Variant = (def as Dictionary).get("shake")
	if typeof(shake) == TYPE_DICTIONARY:
		# 頓幀結束後才震：凍結中畫面不抖，放開的瞬間才有衝擊。
		var delay := maxf(float((def as Dictionary).get("hitstop", 0.0)), float(ctx.get("freeze", (def as Dictionary).get("freeze", 0.0)))) * scale
		var px := float((shake as Dictionary).get("px", 0.0)) * scale
		var time := float((shake as Dictionary).get("time", 0.0))
		var direction: Vector2 = ctx.get("dir", Vector2.ZERO)
		var origin: Vector2 = ctx.get("origin", Vector2.INF)
		if delay > 0.0:
			get_tree().create_timer(delay, true, false, true).timeout.connect(self.shake.bind(px, time, direction, origin))
		else:
			self.shake(px, time, direction, origin)
	if (def as Dictionary).has("screen"):
		EventBus.screen_pulse.emit(StringName(str((def as Dictionary)["screen"])))
	var zoom: Variant = (def as Dictionary).get("zoom")
	if typeof(zoom) == TYPE_DICTIONARY and ZOOM_WHITELIST.has(String(id)) and Settings.zoom_pulse_active():
		EventBus.camera_zoom_pulse.emit(float((zoom as Dictionary).get("amount", 0.0)) * scale * preset_scale("zoom"), float((zoom as Dictionary).get("time", 0.0)))
		_count("zooms")
	if (def as Dictionary).has("hitstop"):
		hitstop(float((def as Dictionary)["hitstop"]) * scale)
	var slowmo: Variant = (def as Dictionary).get("slowmo")
	if typeof(slowmo) == TYPE_DICTIONARY:
		_play_slowmo(slowmo as Dictionary)
	if (def as Dictionary).has("freeze") or ctx.has("freeze"):
		freeze(ctx.get("targets", []), float(ctx.get("freeze", (def as Dictionary).get("freeze", 0.0))) * scale)


## 慢動作只用在白名單情境（reason），可再限制場上敵人數量（max_enemies）；冷卻由 Fx 管理。
func _play_slowmo(def: Dictionary) -> void:
	var limit := int(def.get("max_enemies", 999))
	if get_tree().get_nodes_in_group(&"enemies").size() > limit:
		return
	if Fx.slowmo(str(def.get("reason", "")), float(def.get("scale", 1.0)), float(def.get("time", 0.0))):
		_count("slowmos")


## 鏡頭震動：峰值像素與持續秒數，強度隨時間平方衰減。
func shake(px: float, time: float, direction := Vector2.ZERO, origin := Vector2.INF) -> void:
	if px <= 0.0 or time <= 0.0:
		return
	_count("shakes")
	Fx.shake(minf(px * Settings.get_feel_scale("shake") * preset_scale("shake"), MAX_SHAKE_PX), time, direction, origin)


## 舊資料用「強度」表示的震動（武器、特效資料）。
func shake_strength(strength: float, time: float, direction := Vector2.ZERO, origin := Vector2.INF) -> void:
	shake(strength * STRENGTH_TO_PX, time, direction, origin)


func hitstop(seconds: float) -> void:
	if seconds > 0.0:
		_count("hitstops")
		Fx.hitstop(seconds * Settings.get_feel_scale("hitstop") * preset_scale("hitstop"))


func freeze(nodes: Array, seconds: float) -> void:
	if seconds > 0.0:
		_count("freezes")
		Fx.freeze(nodes, seconds * Settings.get_feel_scale("hitstop") * preset_scale("hitstop"))


## 各系統註冊自己的即時計數（例如粒子數、同時發聲數）：name → Callable（回傳數字）。
func register_counter(counter_name: String, reader: Callable) -> void:
	_gauges[counter_name] = reader


## 目前所有計數：事件計數加上各系統註冊的即時數字。
func read_counters() -> Dictionary:
	var result: Dictionary = {}
	read_counters_into(result)
	return result


## 把所有計數寫進呼叫端提供的字典（診斷面板每秒更新十次，重複使用同一個字典就不會每次配置新的）。
func read_counters_into(out: Dictionary) -> void:
	for key: String in counters.keys():
		out[key] = counters[key]
	for key: String in _gauges.keys():
		var reader: Callable = _gauges[key]
		out[key] = reader.call() if reader.is_valid() else 0


func _count(key: String) -> void:
	counters[key] = int(counters.get(key, 0)) + 1


func _report(key: String, message: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(message)
