class_name HintSign
extends Node2D
## 教學看板：地圖數字字元（1~9）對應 LevelData.hints 的文字，玩家靠近時顯示重點操作說明。
## 牌體是一台立式顯示器（貼圖）；這裡畫的是亮著的螢幕（NE-390）：亮度漸層、掃描線、緩慢下移的亮帶、
## 偶爾閃一下的圖示，以及漫到牌體四周的柔和光暈。不在螢幕外面另外框一圈線。離開畫面時不重畫。

const TEXT_CATALOG := "res://data/levels/ch1_hint_text.json"

## 螢幕在牌體貼圖上的範圍（本地座標；顯示器外框以內）。
const SCREEN := Rect2(-6.0, -21.5, 12.0, 8.5)
## 螢幕的光漫到四周的範圍。
const HALO_SIZE := Vector2(26.0, 20.0)
## 亮帶由上掃到下一次的秒數、圖示每隔幾秒閃一下、一次閃多久。
const SWEEP_SECONDS := 2.6
const BLINK_EVERY := 4.3
const BLINK_SECONDS := 0.12

static var _translations: Dictionary = {}
static var _translations_loaded := false

var text := ""

var _time := 0.0
## 牌體的貼圖；讀不到時是 null，改用簡單畫法。
var _art: Sprite2D


func _ready() -> void:
	LightKit.mark_emissive(self)
	_art = FixtureArt.attach(self, &"hint_sign", Vector2(-8.0, -24.0), Vector2(16.0, 24.0))
	var prompt := WorldPrompt.new()
	# 教學看板教的是「按哪個鍵」：佔位符畫成按鍵帽，鍵鼠與手把各自顯示目前的綁定。
	prompt.keycaps = true
	prompt.text = localized_text(text, Story.language)
	prompt.radius = 64.0
	prompt.offset = Vector2(0, -30)
	add_child(prompt)
	_time = randf() * BLINK_EVERY  # 相鄰的看板不同步
	# 只有在畫面內才更新螢幕。
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(SCREEN.get_center() - HALO_SIZE * 0.5, HALO_SIZE)
	notifier.screen_entered.connect(set_process.bind(true))
	notifier.screen_exited.connect(set_process.bind(false))
	add_child(notifier)
	set_process(false)


static func localized_text(source: String, language: String) -> String:
	if source.is_empty() or language == StoryLocale.SOURCE_LANGUAGE or not StoryLocale.is_supported(language):
		return source
	if not _translations_loaded:
		_translations_loaded = true
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEXT_CATALOG))
		if catalog is Dictionary:
			_translations = catalog
		else:
			push_warning("[HintSign] %s 無法讀取或格式錯誤，沿用看板原文。" % TEXT_CATALOG)
	var entry: Variant = _translations.get(source)
	if entry == null:
		return source
	if not entry is Dictionary:
		push_warning("[HintSign] %s 的「%s」譯文格式錯誤，沿用看板原文。" % [TEXT_CATALOG, source])
		return source
	var localized: Dictionary = entry.duplicate()
	localized["text"] = source
	var missing := StoryLocale.localize(localized, language)
	if not missing.is_empty():
		push_warning(StoryLocale.report("[HintSign] %s 的「%s」" % [TEXT_CATALOG, source], missing, "缺少看板譯文"))
	return localized["text"]


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var glow := LightKit.glow(Palette.CYAN, 1.5 + 0.4 * sin(_time * 3.0))
	if _art != null:
		_draw_screen(glow)
		return
	draw_line(Vector2(0, 0), Vector2(0, -12), Palette.TERRAIN_TOP, 2.0)
	draw_rect(Rect2(-7, -20, 14, 9), Palette.TERRAIN_EDGE)
	draw_rect(Rect2(-7, -20, 14, 9), glow, false, 1.0)
	draw_line(Vector2(0, -18), Vector2(0, -15), glow, 1.5)
	draw_circle(Vector2(0, -13), 0.8, glow)


## 亮著的螢幕：光暈、上亮下暗的底、掃描線、下移的亮帶與圖示。
func _draw_screen(glow: Color) -> void:
	draw_texture_rect(LightKit.soft_texture(), Rect2(SCREEN.get_center() - HALO_SIZE * 0.5, HALO_SIZE), false, Color(Palette.CYAN, 0.1 + 0.03 * sin(_time * 3.0)))
	var top := Color(Palette.CYAN, 0.5)
	var bottom := Color(Palette.CYAN, 0.16)
	draw_polygon(PackedVector2Array([SCREEN.position, Vector2(SCREEN.end.x, SCREEN.position.y), SCREEN.end, Vector2(SCREEN.position.x, SCREEN.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))
	var y := SCREEN.position.y + 1.0
	while y < SCREEN.end.y:
		draw_line(Vector2(SCREEN.position.x, y), Vector2(SCREEN.end.x, y), Color(0.0, 0.05, 0.08, 0.22), 0.5)
		y += 1.5
	var sweep := SCREEN.position.y + fposmod(_time / SWEEP_SECONDS, 1.0) * (SCREEN.size.y - 1.0)
	draw_rect(Rect2(SCREEN.position.x, sweep, SCREEN.size.x, 1.0), Color(Palette.CYAN, 0.35))
	# 圖示：偶爾閃一下（像訊號不穩），其餘時間穩定亮著。
	var blinking := fposmod(_time, BLINK_EVERY) < BLINK_SECONDS and not Settings.get_reduce_flashes()
	var icon := Color(LightKit.glow(Palette.WHITE.lerp(Palette.CYAN, 0.35), 1.6), 0.35 if blinking else 1.0)
	var center := SCREEN.get_center().x
	draw_rect(Rect2(center - 0.8, SCREEN.position.y + 1.4, 1.6, 3.8), icon)
	draw_rect(Rect2(center - 0.8, SCREEN.position.y + 5.9, 1.6, 1.4), icon)
