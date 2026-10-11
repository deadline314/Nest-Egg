class_name Lamp
extends Node2D
## 場景燈：投射陰影的動態光源。風格（光池大小、壞掉、脈動、可用的燈具款式、供電狀況）由所在區段的 LampStyle 決定；
## 壞掉的燈不亮也不閃。電力不足的區域裡，燈依供電狀況分成穩定、接觸不良、快壞了（LampFlicker）：閃的時候光池、
## 它造成的影子、光錐與燈具的發光部位一起變化；每秒亮暗變化不超過 3 次，設定的「減少閃光」打開時改成緩慢起伏。
## 燈具是畫出來的圖（LampFixtures），依這盞燈周圍有什麼來決定怎麼裝：吊在天花板、裝在牆上、立桿或站在地上；
## 周圍沒有天花板也沒有牆時，可以掛在桿子上的款式改成掛在桿子的橫臂下或鎖在桿子上。
## 原點就是發光的位置。燈具與支撐畫在擺設那一層（角色後面），光錐維持在原本的層。

## 亮度追上閃法的速度（每秒）：一步之內就到位，但不是瞬間跳變。
const FLICKER_SLEW := 14.0
## 亮度比例低於這個值時不投影：幾乎全暗的燈（快壞的燈大部分時間）投出來的影子看不見，不付投影的成本、也不佔投影的名額。
const SHADOW_FROM := 0.2
## 快壞的燈暗著的時候電流聲比較小，亮起來的瞬間最大聲。
const BUZZ_IDLE := 0.35
## 支撐的顏色（吊桿、立桿、底座）：受場景的光照亮，所以用深色的鋼。
const SUPPORT_COLOR := Color(0.2, 0.22, 0.27)
const SUPPORT_EDGE := Color(0.42, 0.46, 0.54)
const ROD_WIDTH := 2.0
const POLE_WIDTH := 3.0
const BASE_SIZE := Vector2(10.0, 3.0)
## 掛在桿子上：橫臂比燈具頂端高多少、桿子離燈具邊緣多遠。
const ARM_RISE := 5.0
const ARM_GAP := 7.0
## 熄滅或壞掉時，燈具本體壓暗的程度。
const UNLIT_TINT := Color(0.62, 0.64, 0.7)
const GLOW_INTENSITY := 1.2

## 所在區段給的基準：色調、光池半徑、亮度。實際照出來的光見 light_color、light_radius、light_energy。
var color := Palette.CYAN
var radius := 190.0
var energy := 1.5
## 實際的光：沒有燈具圖時等於基準；有燈具圖時顏色跟著燈具（混一點區段色調），光池與亮度是基準乘上燈具的比例。
## 加入場景時算好。
var light_color := Palette.CYAN
## 燈具的光色裡混進多少基準色調（區段風格的 fixture_tint）：燈具決定是冷白、暖黃還是紅，區段帶一點自己的氣氛。
var zone_tint := 0.18
var light_radius := 190.0
var light_energy := 1.5
## 閃爍的狀態（LampFlicker：stable 穩定、loose 接觸不良、dying 快壞了）。用 use_flicker() 指定。
var flicker_state: StringName = LampFlicker.STABLE
## 量測用：>= 0 時所有會閃的燈固定在「最暗的那一刻」（0）到「正常亮度」（1）之間的這個位置，不再照閃法走。
static var flicker_hold := -1.0
## 亮度脈動頻率（Hz，0 = 不脈動）。
var pulse_hz := 0.0
var dead := false
## 燈下地面的世界 y 座標（濕地倒影、立桿接地）；INF 代表沒有地面。
var floor_y := INF
## 頭上最近的天花板底面的世界 y 座標；INF 代表頭上沒有天花板。
var ceiling_y := INF
## 光錐裡要不要有雨絲：只有下雨的關卡、頭上沒有屋頂的燈才有。
var rain_streaks := false
## 燈具款式（LampFixtures 的 id）；空的代表沒有燈具圖，只有光。
var fixture_id: StringName = &""
## 背後有沒有牆：壁掛的燈具要有牆才算有支撐。
var wall_behind := false
## 立桿或腳架落地處的地面（世界 y）；INF 代表那裡沒有地面。預設和燈下的地面相同，關卡用 settle() 依桿子實際的位置重查。
var support_floor_y := INF
## 左右翻轉：桿子或壁架換到另一邊。
var flipped := false

var _light: PointLight2D
var _shaft: LightShaft
var _fixture: Dictionary = {}
var _prop: PropData
## 實際用的安裝方式：通常是燈具原本的；原本的裝不上而改掛在桿子上時是 pole。
var _mount: StringName = &""
var _body: Node2D
var _art: Sprite2D
var _glow: Sprite2D
## 供電門檻：供電低於它時這盞燈熄滅（讓停電時各盞燈依序熄滅）。
var _power_threshold := randf_range(0.1, 0.95)
var _gate := 1.0
var _pattern := PackedFloat32Array()
var _pattern_offset := 0
var _calm_phase := 0.0
var _buzz := 0.0
## 進關卡後經過的時間：閃法從它算，所以同一盞燈每次進關卡的閃法相同。
var _clock := 0.0
var _flicker := 1.0
var _casts_shadow := true
var _time := 0.0
var _shown_level := -1.0


## 套用區段的燈風格。seed_value 決定是否壞掉，所以同一盞燈每次進關卡都一樣。
## supports＝這盞燈周圍能用的安裝方式（{ceiling, wall, pole, ground: bool}），ordinal＝它在關卡裡的序號（相鄰的燈輪流換款）。
func apply_style(style: LampStyle, seed_value: int, supports := {}, ordinal := 0) -> void:
	if style == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	color = style.color_for(rng)
	radius = style.radius
	energy = style.energy
	zone_tint = style.fixture_tint
	pulse_hz = style.pulse_hz
	dead = rng.randf() < style.dead_chance
	_power_threshold = rng.randf_range(0.1, 0.95)
	if not supports.is_empty():
		use_fixture(LampFixtures.pick(style.fixtures, supports, ordinal, style.fixtures.size() * 7 + int(style.radius)), supports)


## 指定燈具款式：光的顏色與比例跟著燈具走。要在加入場景之前呼叫。
## supports＝周圍能用的安裝方式；燈具原本的安裝方式裝不上、但可以掛在桿子上時改用桿子。不給就用原本的。
func use_fixture(id: StringName, supports := {}) -> void:
	fixture_id = id
	_fixture = LampFixtures.fixture(id)
	_prop = LampFixtures.prop(id) if not _fixture.is_empty() else null
	if _prop == null:
		_fixture = {}
		fixture_id = &""
		_mount = &""
		return
	_mount = LampFixtures.mount_for(_fixture, supports)
	support_floor_y = floor_y
	_stand_on_floor()


## 依支撐實際落地的位置確認地面。floor_at＝給世界 x、回傳那一欄在這盞燈下方的地面 y（沒有回傳 INF）。
## 桿子那一側沒有地面（坑洞、平台邊緣）就翻到另一側；兩側都沒有時維持原樣，is_supported() 會回報沒有支撐。
func settle(floor_at: Callable) -> void:
	if mount() != &"pole" and mount() != &"ground":
		return
	for side: bool in [flipped, not flipped]:
		flipped = side
		support_floor_y = floor_at.call(position.x + support_offset_x())
		if support_floor_y != INF:
			break
	_stand_on_floor()


## 支撐（桿子、腳架的中心）相對於發光位置的水平距離。
func support_offset_x() -> float:
	if _prop == null:
		return 0.0
	if _hangs_from_arm():
		var reach := _prop.size.x * 0.5 + ARM_GAP
		return _centre_x() + (-reach if flipped else reach)
	var at := float(_fixture.get("pole_at", 0.5)) if mount() == &"pole" else 0.5
	var offset := _prop.size.x * at - _prop.light_offset.x
	return -offset if flipped else offset


## 燈具圖的水平中心相對於發光位置。
func _centre_x() -> float:
	var offset := _prop.size.x * 0.5 - _prop.light_offset.x
	return -offset if flipped else offset


## 原本吊在天花板的款式改掛在桿子的橫臂下。
func _hangs_from_arm() -> bool:
	return _mount == &"pole" and _fixture.get("pole", &"") == &"arm"


## 站在地上的燈具：整盞移到地面，發光的位置是燈頭。
func _stand_on_floor() -> void:
	if mount() == &"ground" and support_floor_y != INF:
		position.y = support_floor_y - (_prop.size.y - _prop.light_offset.y)


## 指定閃爍的狀態。seed_value 決定用哪一條閃法、從哪一步開始，所以同一盞燈每次進關卡都一樣。
## 會脈動的警示燈不再疊上閃爍；沒有可用的閃法時維持穩定。
func use_flicker(state: StringName, seed_value: int) -> void:
	flicker_state = LampFlicker.STABLE
	_pattern = PackedFloat32Array()
	_buzz = 0.0
	if state == LampFlicker.STABLE or pulse_hz > 0.0 or LampFlicker.pattern_count(state) == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_pattern = LampFlicker.pattern(state, rng.randi_range(0, LampFlicker.pattern_count(state) - 1))
	_pattern_offset = rng.randi_range(0, _pattern.size() - 1)
	_calm_phase = rng.randf()
	_buzz = LampFlicker.buzz(state)
	flicker_state = state


## 這盞燈現在的電流聲（0～1）：只有快壞的燈有；熄滅、停電時沒有，亮起來的瞬間最大聲。
func buzz_level() -> float:
	if _buzz <= 0.0 or dead or _light == null or not _light.enabled:
		return 0.0
	return _buzz * clampf(BUZZ_IDLE + (1.0 - BUZZ_IDLE) * _flicker, 0.0, 1.0)


## 實際用的安裝方式（ceiling、wall、pole、ground）；沒有燈具圖時是空的。
func mount() -> StringName:
	return _mount


## 這盞燈有沒有支撐（測試與場景檢查用）：有燈具圖，而且吊得到天花板、接得到地面，或裝在牆上。
func is_supported() -> bool:
	match mount():
		&"ceiling":
			return ceiling_y != INF
		&"pole", &"ground":
			return support_floor_y != INF
		&"wall":
			return wall_behind
	return false


func _ready() -> void:
	_time = randf() * TAU
	_resolve_light()
	_build_fixture()
	if dead:
		set_process(false)
		_show_level(0.0)
		return
	_light = LightKit.create_point_light(light_color, light_radius, light_energy, true)
	add_child(_light)
	# 往四周發光的款式（光錐比例 0）沒有光錐，只留地面的反光。
	var shaft_scale := float(_fixture.get("shaft", 1.0))
	_shaft = LightShaft.new()
	_shaft.color = light_color
	_shaft.cone = shaft_scale > 0.0
	_shaft.length = minf(light_radius * 0.7, 150.0) * (shaft_scale if _shaft.cone else 0.6)
	_shaft.half_width = _shaft.length * 0.32
	if _prop != null:
		# 有燈具圖：光暈交給發光部位與泛光；長條形的發光面從整條往下照；朝一邊的燈頭光錐跟著偏。
		_shaft.halo_radius = 0.0
		_shaft.source_half_width = _prop.size.x * float(_fixture.get("emit", 0.0)) * 0.5
		var aim := float(_fixture.get("aim_x", 0.0))
		_shaft.direction = Vector2(-aim if flipped else aim, 1.0).normalized()
	_shaft.floor_y = floor_y
	_shaft.rain_streaks = rain_streaks
	_shaft.source = _light
	_shaft.position = Vector2(0, 3)
	add_child(_shaft)
	_show_level(1.0)


func _resolve_light() -> void:
	light_color = color
	light_radius = radius
	light_energy = energy
	if _prop != null:
		light_color = _prop.light_color.lerp(color, zone_tint)
		light_radius = radius * float(_fixture["radius"])
		light_energy = energy * float(_fixture["energy"])


func _build_fixture() -> void:
	if _prop == null:
		return
	var texture := LitTextures.load_texture(_prop.texture, Vector2i(_prop.size) * PropData.TEXTURE_SCALE)
	_art = Sprite2D.new()
	_art.texture = texture
	_art.centered = false
	_art.scale = _prop.size / Vector2(texture.get_size())
	_art.flip_h = flipped
	_art.position = _top_left()
	_body = Node2D.new()
	_body.z_as_relative = false
	_body.z_index = WorldLayers.PROPS
	_body.draw.connect(_draw_supports)
	add_child(_body)
	_body.add_child(_art)
	var glow := RigLibrary.optional_texture(_prop.glow_path()) if _prop.has_glow else null
	if glow == null:
		return
	_glow = Sprite2D.new()
	_glow.texture = glow
	_glow.centered = false
	_glow.scale = _prop.size / Vector2(glow.get_size())
	_glow.flip_h = flipped
	_glow.position = _top_left()
	_glow.material = LightKit.additive_emissive_material()
	_body.add_child(_glow)


## 這盞燈照到 point 的程度 0～1（離燈越遠越弱，熄滅、壞掉、停電時為 0）。
func light_at(point: Vector2) -> float:
	if dead or _light == null or not _light.enabled:
		return 0.0
	var falloff := clampf(1.0 - global_position.distance_to(point) / maxf(1.0, light_radius), 0.0, 1.0)
	return falloff * clampf(_light.energy / maxf(light_energy, 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var gate := LightKit.power_gate(LightKit.lamp_power, _power_threshold)
	if not is_equal_approx(gate, _gate):
		_gate = gate
		_light.enabled = gate > 0.0
	if gate <= 0.0:
		if _shaft != null:
			_shaft.intensity = 0.0
		_show_level(0.0)
		return
	var level := light_energy * gate
	if pulse_hz > 0.0:
		level *= 0.55 + 0.45 * sin(_time * TAU * pulse_hz)
	_light.energy = level * _flicker_level(delta)
	var shown := clampf(_light.energy / maxf(light_energy, 0.01), 0.0, 1.5)
	if (shown >= SHADOW_FROM) != _casts_shadow:
		# 亮回來的那一格就恢復投影，光池與影子同時出現；名額由光源預算下一次評估時校正。
		_casts_shadow = not _casts_shadow
		_light.set_meta(LightKit.META_WANTS_SHADOW, _casts_shadow)
		_light.shadow_enabled = _casts_shadow and _light.visible
	if _shaft != null:
		_shaft.intensity = shown
	_show_level(shown)


## 這一格的閃爍亮度比例。穩定的燈永遠是 1。
func _flicker_level(delta: float) -> float:
	if flicker_state == LampFlicker.STABLE:
		return 1.0
	_clock += delta
	var target: float
	if flicker_hold >= 0.0:
		target = lerpf(LampFlicker.darkest(flicker_state), 1.0, flicker_hold)
	elif LampFlicker.reduced():
		target = LampFlicker.calm_level(flicker_state, _clock, _calm_phase)
	else:
		target = LampFlicker.level_at(_pattern, _clock, _pattern_offset)
	_flicker = move_toward(_flicker, target, delta * FLICKER_SLEW)
	return _flicker


## 燈具的發光部位與本體跟著實際亮度變化（0＝熄滅）。數值沒變就不動。
func _show_level(level: float) -> void:
	if is_equal_approx(level, _shown_level):
		return
	_shown_level = level
	if _glow != null:
		_glow.visible = level > 0.01
		_glow.self_modulate = LightKit.glow(Color.WHITE.lerp(color, zone_tint), GLOW_INTENSITY * minf(level, 1.2))
	if _art != null:
		_art.self_modulate = UNLIT_TINT.lerp(Color.WHITE, clampf(level, 0.0, 1.0))
	if _prop == null:
		queue_redraw()


func _draw() -> void:
	if _prop == null:
		# 沒有燈具圖時的安全預設：一小段燈座，亮的時候有一條發光的燈管。
		draw_rect(Rect2(-6, -2, 12, 3), Palette.TERRAIN_TOP)
		var lit := not dead and _shown_level > 0.01
		draw_rect(Rect2(-4, 1, 8, 2), LightKit.glow(light_color, 2.5 * _shown_level) if lit else Color(light_color.darkened(0.7), 0.5))


## 支撐：吊桿接到天花板；立桿接到地面（掛在桿子上的款式多一段橫臂與吊鉤）。畫在燈具圖後面。
func _draw_supports() -> void:
	var top_left := _top_left()
	match mount():
		&"ceiling":
			if ceiling_y != INF:
				var top := ceiling_y - global_position.y
				_draw_bar(Rect2(_centre_x() - ROD_WIDTH * 0.5, top, ROD_WIDTH, maxf(0.0, top_left.y + 2.0 - top)))
		&"pole":
			if support_floor_y == INF:
				return
			var x := support_offset_x()
			var bottom := support_floor_y - global_position.y
			var from := top_left.y + _prop.size.y * 0.5
			if _hangs_from_arm():
				from = top_left.y - ARM_RISE
				var centre := _centre_x()
				var left := minf(x, centre) - ROD_WIDTH * 0.5
				_body.draw_rect(Rect2(left, from, absf(x - centre) + ROD_WIDTH, ROD_WIDTH), SUPPORT_COLOR)
				_body.draw_rect(Rect2(left, from, absf(x - centre) + ROD_WIDTH, 1.0), SUPPORT_EDGE)
				_body.draw_line(Vector2(x, from + 9.0), Vector2(lerpf(x, centre, 0.6), from + 1.0), SUPPORT_COLOR, 1.5)
				_draw_bar(Rect2(centre - ROD_WIDTH * 0.5, from, ROD_WIDTH, ARM_RISE + 2.0))
			elif _fixture.get("mount") == &"wall":
				# 原本壁掛的款式整個鎖在桿子上，桿子從燈具頂端一路到地面。
				from = top_left.y - 2.0
			_draw_bar(Rect2(x - POLE_WIDTH * 0.5, from, POLE_WIDTH, maxf(0.0, bottom - from)))
			_draw_bar(Rect2(x - BASE_SIZE.x * 0.5, bottom - BASE_SIZE.y, BASE_SIZE.x, BASE_SIZE.y))


## 燈具圖左上角相對於發光位置的座標（翻轉時發光位置仍在原點）。
func _top_left() -> Vector2:
	return Vector2(_prop.light_offset.x - _prop.size.x if flipped else -_prop.light_offset.x, -_prop.light_offset.y)


## 一段鋼條：深色本體加左側一條亮邊（光從左上來，和其他擺設一致）。
func _draw_bar(rect: Rect2) -> void:
	if rect.size.y <= 0.0:
		return
	_body.draw_rect(rect, SUPPORT_COLOR)
	_body.draw_rect(Rect2(rect.position, Vector2(1.0, rect.size.y)), SUPPORT_EDGE)
