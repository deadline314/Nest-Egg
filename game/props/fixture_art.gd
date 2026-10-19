class_name FixtureArt
## 關卡固定物件（門、梯子、提示牌、開關箱、可擊碎牆、閘門）的賽璐璐貼圖。
## 貼圖由 tools/assets/cel_fixtures.py 產生，每個世界像素 TEXELS_PER_PIXEL 個貼圖像素。
## 物件本身多半是自發光（狀態燈、提示符號），貼圖要受環境光與燈光影響，所以做成墊在物件後面的子節點。
## 貼圖讀不到時記錄一次路徑並回傳 null，呼叫端退回原本的簡單畫法，不會讓關卡壞掉。

const FOLDER := "res://art/environment/fixtures/"
const TEXELS_PER_PIXEL := 8.0
const BREAKABLE_BODIES := {
	BreakableData.Look.CRATE: &"breakable_crate",
	BreakableData.Look.BARREL: &"breakable_barrel",
	BreakableData.Look.GLASS: &"breakable_glass",
}
const MECHANISM_PARTS := {
	MechanismData.Kind.LIFT: [&"lift_deck", &"lift_rail", &"lift_stop"],
	MechanismData.Kind.POWER_SWITCH: [&"power_switch_on", &"power_switch_off"],
}
const RUBBLE_LIFETIME := 0.65

static var _cache: Dictionary = {}


static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := FOLDER + String(id) + ".png"
	var loaded := RigLibrary.optional_texture(path)
	if loaded == null:
		push_error("[FixtureArt] 找不到固定物件貼圖，改用簡單畫法：%s" % path)
	_cache[id] = loaded
	return loaded


## 建立墊在 owner 後面的貼圖節點，左上角在 top_left（owner 的本地座標），大小是 world_size（世界像素）。
## tiled＝false 把整張貼圖放進這個大小；true 依貼圖原本的密度平鋪（牆、梯子、捲門）。貼圖讀不到回傳 null。
static func attach(owner: Node2D, id: StringName, top_left: Vector2, world_size: Vector2, tiled := false) -> Sprite2D:
	var loaded := texture(id)
	if loaded == null:
		return null
	var sprite := Sprite2D.new()
	sprite.name = "Art_" + String(id)
	sprite.texture = loaded
	sprite.centered = false
	sprite.show_behind_parent = true
	sprite.position = top_left
	owner.add_child(sprite)
	resize(sprite, world_size, tiled)
	return sprite


## 改變貼圖節點的大小（閘門開關時高度會變）。
static func resize(sprite: Sprite2D, world_size: Vector2, tiled: bool) -> void:
	if tiled:
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ZERO, world_size * TEXELS_PER_PIXEL)
		sprite.scale = Vector2.ONE / TEXELS_PER_PIXEL
	else:
		var size := sprite.texture.get_size()
		sprite.scale = Vector2(world_size.x / maxf(1.0, size.x), world_size.y / maxf(1.0, size.y))


static func breakable_body(look: BreakableData.Look) -> StringName:
	return BREAKABLE_BODIES.get(look, &"")


static func throwable_body(look: ThrowableData.Look) -> StringName:
	match look:
		ThrowableData.Look.CRATE: return &"breakable_crate"
		ThrowableData.Look.BARREL: return &"breakable_barrel"
	return &""


static func body_parts(id: StringName) -> Array[StringName]:
	return [id, StringName(String(id) + "_damaged"), StringName(String(id) + "_broken")] if id != &"" else []


## Audit metadata never loads a whole texture into the cache just to check a path.
static func missing_parts(ids: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for id: StringName in ids:
		var path := FOLDER + String(id) + ".png"
		if not ResourceLoader.exists(path, "Texture2D"):
			missing.append(path)
	return missing


static func damage(sprite: Sprite2D, id: StringName, ratio: float, world_size: Vector2) -> void:
	if sprite == null or id == &"":
		return
	var wanted := StringName(String(id) + "_damaged") if ratio < 0.7 else id
	var loaded := texture(wanted)
	if loaded != null:
		sprite.texture = loaded
		resize(sprite, world_size, false)


## Presentation only: sibling debris dies with the level, has no collision or rewards.
## Never called by checkpoint restoration.
static func rubble(owner: Node2D, id: StringName, body_size: Vector2) -> Sprite2D:
	if id == &"" or not owner.is_inside_tree():
		return null
	var loaded := texture(StringName(String(id) + "_broken"))
	if loaded == null:
		return null
	var sprite := Sprite2D.new()
	sprite.name = "FixtureRubble"
	sprite.texture = loaded
	sprite.centered = false
	owner.get_parent().add_child(sprite)
	sprite.global_position = owner.global_position
	sprite.z_index = owner.z_index
	var size := Vector2(body_size.x, minf(body_size.y * 0.35, 12.0))
	resize(sprite, size, false)
	sprite.position += Vector2(-size.x * 0.5, -size.y)
	var tween := sprite.create_tween()
	tween.tween_interval(RUBBLE_LIFETIME * 0.55)
	tween.tween_property(sprite, "modulate:a", 0.0, RUBBLE_LIFETIME * 0.45)
	tween.tween_callback(sprite.queue_free)
	return sprite


## 測試用：清掉快取，下次重新讀檔。
static func clear_cache() -> void:
	_cache.clear()
