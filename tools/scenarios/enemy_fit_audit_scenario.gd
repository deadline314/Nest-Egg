extends ScenarioBase
## 人形敵人外觀與判定對照表（NE-75～82）：每個敵人列出碰撞框、畫面高度、頭探出碰撞框的高度、
## 部位判定中心是否落在畫面範圍內、槍口位置（雷射、火焰、砲彈、機槍子彈的起點都取這個點）。
## --levels：改列出兩章關卡裡每種敵人出現的欄與當地的光影設定（拍「在出現的關卡光影下清楚可辨」要看哪些光影）。
## --contrast：每個敵人站在自己出現的關卡光影下，量輪廓對比（算法同 tools/readability_check.gd，門檻 MIN_ENEMY_CONTRAST）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=enemy_fit_audit [--enemies=a,b] [--levels] [--contrast]

const DEFAULT_ENEMIES := ["grunt", "elite_grunt", "sniper", "slasher", "stalker", "flamer", "mortar", "shield_rusher", "heavy_gunner", "warden", "reclaimer"]
## 頭探出碰撞框的合理上限（像素）；超過代表碰撞框明顯偏矮。
const HEAD_OVERSHOOT_LIMIT := 14.0
## 敵人在自己出現的光影（--levels 列出來的）；Boss 不在開場的敵人群組裡，手動補上。
const LIGHTING_OF := {
	"sniper": ["freight", "residential"], "slasher": ["shaft_deep"], "stalker": ["residential"],
	"flamer": ["power_room", "shaft_deep"], "mortar": ["facility", "freight"], "shield_rusher": ["freight", "market", "power_room"],
	"heavy_gunner": ["power_room", "residential"], "warden": ["hangar"], "reclaimer": ["reclaimer_arena"],
}
const MIN_ENEMY_CONTRAST := 0.45
const CONTRAST_RING := 20.0


func run() -> void:
	var ids: PackedStringArray = PackedStringArray(DEFAULT_ENEMIES)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			ids = arg.trim_prefix("--enemies=").split(",", false)
		elif arg == "--levels":
			await _list_levels()
			return
		elif arg == "--contrast":
			await _measure_contrast(ids)
			return
	await open_arena("res://data/lighting/transfer.tres", 6.0)
	print("| 敵人 | 碰撞框 | 畫面高 | 頭探出 | 畫面寬 | 槍口(相對腳底) | 胸高/碰撞框中心 | 部位判定 |")
	print("|---|---|---|---|---|---|---|---|")
	for id in ids:
		await _audit(id)
	await finish()


func _audit(id: String) -> void:
	var path := "res://data/enemies/%s.tres" % id
	if not ResourceLoader.exists(path):
		push_error("[EnemyFitAudit] 找不到敵人資料：%s" % path)
		return
	var enemy := spawn_enemy(path, 20.0)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	await settle(4)
	if enemy.rig == null:
		print("| %s | 沒有骨架外觀 | | | | | | |" % id)
		enemy.queue_free()
		return
	var bounds := _visual_bounds(enemy.rig)
	var feet := enemy.global_position
	var body := enemy.data.body_size
	var overshoot := (feet.y - body.y) - bounds.position.y
	var muzzle := enemy.rig.muzzle_global() - feet
	var parts_note: PackedStringArray = []
	for part in enemy.hurtbox.parts:
		var inside := bounds.grow(2.0).has_point(part.global_position)
		parts_note.append("%s%s" % [part.part_id, "" if inside else "(畫面外)"])
	print("| %s | %dx%d | %d | %s%.0f%s | %d | (%d, %d) | %d / %d | %s |" % [
		id, body.x, body.y, bounds.size.y, "+" if overshoot > 0 else "", overshoot,
		" ⚠" if overshoot > HEAD_OVERSHOOT_LIMIT else "", bounds.size.x, muzzle.x, muzzle.y,
		-(enemy.rig.bone(&"chest").global_position.y - feet.y), body.y * 0.5, ", ".join(parts_note)])
	enemy.queue_free()


## 骨架上所有看得見的零件（不含手持武器）合起來的世界座標範圍。
func _visual_bounds(rig: CharacterRig) -> Rect2:
	var total := Rect2()
	var first := true
	for sprite in rig._part_sprites:
		if sprite == null or sprite.texture == null or not sprite.is_visible_in_tree():
			continue
		var xf := sprite.get_global_transform()
		var r := sprite.get_rect()
		var rect := Rect2(xf * r.position, Vector2.ZERO)
		for corner in [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			rect = rect.expand(xf * corner)
		total = rect if first else total.merge(rect)
		first = false
	return total


func _list_levels() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	for path in ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres"]:
		var data := load(path) as LevelData
		var lvl := Level.new()
		lvl.configure(data)
		add_child(lvl)
		await settle(10)
		var seen := {}
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.data == null:
				continue
			var tile := int(enemy.global_position.x / 16.0)
			var zone_name := "(無)"
			var best := -1
			for zone in data.lighting_zones:
				if zone.start_tile <= tile and zone.start_tile > best:
					best = zone.start_tile
					zone_name = str(zone.profile.resource_path.get_file().get_basename())
			var key := "%s @ %s" % [enemy.data.id, zone_name]
			seen[key] = int(seen.get(key, 0)) + 1
		var keys := seen.keys()
		keys.sort()
		for key in keys:
			print("LEVEL %s | %s x%d" % [path.get_file(), key, seen[key]])
		lvl.queue_free()
		await settle(3)


func _measure_contrast(ids: PackedStringArray) -> void:
	print("| 敵人 | 光影 | 對比 | 結果 |")
	print("|---|---|---|---|")
	var by_light := {}
	for id in ids:
		for light in LIGHTING_OF.get(id, []):
			by_light[light] = by_light.get(light, []) + [id]
	for light in by_light:
		await open_arena("res://data/lighting/%s.tres" % light, 6.0)
		for id in by_light[light]:
			var enemy := spawn_enemy("res://data/enemies/%s.tres" % id, 12.0)
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
			place_player(8.0)
			await wait(1.4)
			enemy.global_position = Vector2(12.0 * 16.0, FLOOR_Y)
			await settle(3)
			var image := get_viewport().get_texture().get_image()
			var value := _contrast(image, _visual_bounds(enemy.rig))
			print("| %s | %s | %.2f | %s |" % [id, light, value, "OK" if value >= MIN_ENEMY_CONTRAST else "偏暗"])
			enemy.queue_free()
			await settle(3)
		level.queue_free()
		await settle(3)


## 亮部比周圍亮多少，或身體比周圍暗多少（剪影），取較大者；方框是世界座標。
func _contrast(image: Image, world_box: Rect2) -> float:
	var to_screen := get_viewport().get_canvas_transform()
	var box := _screen_rect(image, to_screen, world_box)
	var ring := _screen_rect(image, to_screen, world_box.grow(CONTRAST_RING))
	var inner := _luma_values(image, box)
	var outer := _luma_values(image, ring, box)
	if inner.is_empty() or outer.is_empty():
		return 0.0
	inner.sort()
	var outer_mean := 0.0
	for v in outer:
		outer_mean += v
	outer_mean /= outer.size()
	var bright := (inner[int((inner.size() - 1) * 0.9)] - outer_mean) / (outer_mean + 0.02)
	var dark := (outer_mean - inner[int((inner.size() - 1) * 0.5)]) / (outer_mean + 0.02)
	return maxf(bright, dark)


func _screen_rect(image: Image, to_screen: Transform2D, world_rect: Rect2) -> Rect2i:
	var a := to_screen * world_rect.position
	var b := to_screen * world_rect.end
	return Rect2i(Vector2i(a.floor()), Vector2i((b - a).ceil())).intersection(Rect2i(Vector2i.ZERO, image.get_size()))


## 方框內像素的亮度；exclude 內的像素不算（量外圈用）。
func _luma_values(image: Image, rect: Rect2i, exclude := Rect2i()) -> Array[float]:
	var values: Array[float] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if exclude.has_point(Vector2i(x, y)):
				continue
			values.append(LightKit.luminance(image.get_pixel(x, y)))
	return values
