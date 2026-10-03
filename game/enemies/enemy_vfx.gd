class_name EnemyVfx
extends RefCounted
## 敵人專屬特效（資料驅動，art/vfx/enemies/<敵人 id>.json）：腳步揚塵與震動、受擊火花、死亡演出、招式狀態切換時的特效。
## 每個敵人自己一份，不共用（測試會檢查：有檔案、死亡演出彼此不同）。檔案缺失或格式錯誤時記錄具體位置並用安全的預設，不會崩潰。
##
## 檔案格式（所有欄位都可省略）：
##   step    {every: 腳步間隔（像素）, dust: 揚塵數量, spread: 揚塵散開, color: 揚塵顏色, shake: 每步鏡頭震動, spark: 腳底火花數量, spark_color}
##   hit     {color: 火花色, amount: 數量, speed: 速度, light: 受擊閃光強度, kind: spark|arc|smoke|steam}
##   death   {bursts: [{kind, color, amount, speed, life}], light: {color, radius, energy, time}, shake, hitstop, shock: {radius, strength}, flare, extras: [smoke|steam|arc|embers|coolant|dust|fire|shards|lightning],
##            dissolve: {time, color, rise, edge, delay}（燒融：零件逐塊燒掉、邊緣發光、沿著身體噴餘燼）, sound}
##   burst 的 kind：spark（預設，火花）、ember、smoke、fire（火球）、shard、flare、arc（電弧簇）；amount、speed、life 的意義依 kind 而定。
##   states  {狀態名稱: {bursts: [...], light: {...}, shake, dust, steam, sound, at: feet|center|muzzle}}   進入該狀態時播放一次
## 顏色用 "#rrggbb"。

const PATH := "res://art/vfx/enemies/%s.json"

var _data: Dictionary = {}
var _owner_id := ""
var _step_left := 0.0
var _last_x := 0.0
var _has_last := false


static func load_for(enemy_id: String) -> EnemyVfx:
	var vfx := EnemyVfx.new()
	vfx._owner_id = enemy_id
	var path := PATH % enemy_id
	if ResourceLoader.exists(path):
		vfx._data = RigLibrary.load_json(path)
	else:
		RigLibrary.report_once("vfx:" + enemy_id, "[EnemyVfx] %s 沒有特效資料，不播放專屬特效。" % path)
	return vfx


## 每個物理影格呼叫：依移動距離播放腳步特效。airborne 或不在地面時不播。
func tick_step(position: Vector2, on_floor: bool) -> void:
	var step: Dictionary = _data.get("step", {})
	if step.is_empty():
		return
	if not _has_last:
		_last_x = position.x
		_has_last = true
	var moved := absf(position.x - _last_x)
	_last_x = position.x
	if not on_floor:
		return
	_step_left -= moved
	if _step_left > 0.0:
		return
	_step_left = maxf(6.0, float(step.get("every", 24.0)))
	var feet := position + Vector2(0, -1)
	if int(step.get("dust", 0)) > 0:
		Fx.dust(feet, int(step["dust"]), float(step.get("spread", 30.0)))
	if int(step.get("spark", 0)) > 0:
		Fx.burst(feet, _color(step.get("spark_color", "#ffd070")), int(step["spark"]), 90.0, 0.2)
	if float(step.get("shake", 0.0)) > 0.0:
		Fx.shake(float(step["shake"]), 0.08)


func play_hit(at: Vector2, from_direction: Vector2) -> void:
	var hit: Dictionary = _data.get("hit", {})
	if hit.is_empty():
		return
	var color := _color(hit.get("color", "#ffffff"))
	var amount := int(hit.get("amount", 6))
	match str(hit.get("kind", "spark")):
		"smoke":
			Fx.dust(at, amount, float(hit.get("speed", 40.0)))
		"steam":
			Fx.steam(at)
			Fx.impact(at, from_direction, color, maxi(2, amount / 2))
		"arc":
			Fx.burst(at, color, amount, float(hit.get("speed", 160.0)), 0.18)
			Fx.impact(at, from_direction, color, 3)
		_:
			Fx.impact(at, from_direction, color, amount)
	if float(hit.get("light", 0.0)) > 0.0:
		Fx.flash_light(at, color, 36.0, float(hit["light"]), 0.06)


func play_death(center: Vector2, feet: Vector2, host: Node = null, rig: CharacterRig = null) -> void:
	var death: Dictionary = _data.get("death", {})
	for burst: Variant in death.get("bursts", []):
		_play_burst(burst as Dictionary, center)
	var light: Dictionary = death.get("light", {})
	if not light.is_empty():
		Fx.flash_light(center, _color(light.get("color", "#ffffff")), float(light.get("radius", 70.0)), float(light.get("energy", 1.2)), float(light.get("time", 0.25)))
	var flare: Dictionary = death.get("flare", {})
	if not flare.is_empty():
		Fx.flare(center, _color(flare.get("color", "#ffffff")), float(flare.get("size", 50.0)), float(flare.get("life", 0.16)))
	var shock: Dictionary = death.get("shock", {})
	if not shock.is_empty():
		Fx.shock(center, float(shock.get("radius", 60.0)), float(shock.get("strength", 0.04)), _color(shock.get("color", "#ffd9a0")), float(shock.get("time", 0.5)))
	var dissolve: Dictionary = death.get("dissolve", {})
	if not dissolve.is_empty() and host != null and rig != null:
		_start_dissolve(host, rig, dissolve)
	var accent := _color(death.get("accent", "#ff8a2a"))
	for extra: Variant in death.get("extras", []):
		match str(extra):
			"smoke":
				Fx.smoke(center, 8, 12.0, 1.3, 20.0)
			"steam":
				for i in 5:
					Fx.steam(center + Vector2(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0)))
			"arc":
				Fx.lightning(center, Color("35e0ff"), 6, 34.0, 0.22)
			"lightning":
				Fx.lightning(center, accent, 8, 44.0, 0.3)
			"embers":
				Fx.embers(center + Vector2(0, -4), Color("ff8a2a"), 12, 80.0, 1.2, 14.0)
			"fire":
				Fx.fire(center, 12.0, accent, 7, 0.5)
			"shards":
				Fx.shards(center, accent, 7, 220.0, 1.0, 7.0)
			"coolant":
				Fx.splash(feet)
				Fx.sparks(center, Color("7fe8ff"), 10, 120.0, 0.5, Vector2.UP, 2.2)
				Fx.smoke(center, 4, 10.0, 1.0, 16.0, Color(0.5, 0.8, 0.9, 0.35))
			"dust":
				Fx.dust(feet, 8, 60.0)
			_:
				RigLibrary.report_once("vfx_extra:%s:%s" % [_owner_id, extra], "[EnemyVfx] %s 的死亡特效沒有「%s」" % [PATH % _owner_id, extra])
	if float(death.get("shake", 0.0)) > 0.0:
		Fx.shake(float(death["shake"]), 0.14)
	if float(death.get("hitstop", 0.0)) > 0.0:
		Fx.hitstop(float(death["hitstop"]))


## 進入狀態時的特效。at＝feet／center／muzzle 之一（預設 center）；muzzle 由呼叫者傳入。
func play_state(state: StringName, feet: Vector2, center: Vector2, muzzle: Vector2) -> void:
	var states: Dictionary = _data.get("states", {})
	if not states.has(String(state)):
		return
	var def: Dictionary = states[String(state)]
	var at := center
	match str(def.get("at", "center")):
		"feet":
			at = feet
		"muzzle":
			at = muzzle
	for burst: Variant in def.get("bursts", []):
		_play_burst(burst as Dictionary, at)
	var light: Dictionary = def.get("light", {})
	if not light.is_empty():
		Fx.flash_light(at, _color(light.get("color", "#ffffff")), float(light.get("radius", 60.0)), float(light.get("energy", 1.2)), float(light.get("time", 0.2)))
	if int(def.get("dust", 0)) > 0:
		Fx.dust(feet, int(def["dust"]), float(def.get("spread", 40.0)))
	if bool(def.get("steam", false)):
		Fx.steam(at)
	if float(def.get("shake", 0.0)) > 0.0:
		Fx.shake(float(def["shake"]), 0.1)
	if def.has("sound"):
		Sfx.play(StringName(str(def["sound"])), float(def.get("sound_db", -6.0)))


## 資料裡的狀態名稱列表（測試用：確認引用的狀態存在於敵人腳本）。
func state_names() -> PackedStringArray:
	var names := PackedStringArray()
	for key: Variant in (_data.get("states", {}) as Dictionary).keys():
		names.append(str(key))
	return names


func is_empty() -> bool:
	return _data.is_empty()


func _play_burst(def: Dictionary, at: Vector2) -> void:
	var color := _color(def.get("color", "#ffffff"))
	var amount := int(def.get("amount", 8))
	var speed := float(def.get("speed", 120.0))
	var life := float(def.get("life", 0.35))
	match str(def.get("kind", "spark")):
		"ember":
			Fx.embers(at, color, amount, speed * 0.5, life * 2.0)
		"smoke":
			Fx.smoke(at, amount, 10.0, life * 2.0, speed * 0.12, Color(color.r * 0.4, color.g * 0.4, color.b * 0.45, 0.5))
		"fire":
			Fx.fire(at, speed * 0.1, color, amount, life)
		"shard":
			Fx.shards(at, color, amount, speed, life * 2.0, 7.0)
		"flare":
			Fx.flare(at, color, speed, life)
		"arc":
			Fx.lightning(at, color, amount, speed * 0.25, life)
		_:
			Fx.burst(at, color, amount, speed, life)


## 燒融：零件逐塊燒掉（邊緣發光），同時沿著身體噴餘燼與火星；進度由 host 上的補間驅動。
func _start_dissolve(host: Node, rig: CharacterRig, def: Dictionary) -> void:
	var time := maxf(0.2, float(def.get("time", 0.9)))
	var edge := _color(def.get("color", "#ff7a1a"))
	var rise := float(def.get("rise", 1.0))
	var width := float(def.get("edge", 0.1))
	var tween := host.create_tween()
	var last := [0.0]
	if float(def.get("delay", 0.0)) > 0.0:
		tween.tween_interval(float(def["delay"]))
	tween.tween_method(func(v: float) -> void:
		if not is_instance_valid(rig):
			return
		rig.set_dissolve(v, edge, rise, width)
		var step := v - float(last[0])
		last[0] = v
		var count := int(step * 40.0) + (1 if randf() < step * 40.0 - floorf(step * 40.0) else 0)
		for i in count:
			var at := rig.body_point(clampf(v + randf_range(-0.2, 0.2) if rise > 0.0 else 1.0 - v + randf_range(-0.2, 0.2), 0.0, 1.0), 9.0)
			if randf() < 0.6:
				Fx.embers(at, edge, 1, 55.0, 0.9, 2.0)
			else:
				Fx.sparks(at, edge, 1, 90.0, 0.35, Vector2.UP, 2.4, 80.0)
		, 0.0, 1.0, time)


static func _color(value: Variant) -> Color:
	var text := str(value)
	return Color(text) if text.begins_with("#") else Color.WHITE
