class_name HintSign
extends Node2D
## 教學看板：地圖數字字元（1~9）對應 LevelData.hints 的文字，玩家靠近時顯示重點操作說明。

const TEXT_CATALOG := "res://data/levels/ch1_hint_text.json"

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
		# 牌體是貼圖；這裡只畫螢幕上發亮的驚嘆號與螢幕的亮框，暗處也找得到。
		draw_rect(Rect2(-6.0, -21.5, 12.0, 8.5), Color(glow, 0.6), false, 1.0)
		draw_line(Vector2(0, -20.3), Vector2(0, -16.4), glow, 1.6)
		draw_circle(Vector2(0, -14.6), 0.9, glow)
		return
	draw_line(Vector2(0, 0), Vector2(0, -12), Palette.TERRAIN_TOP, 2.0)
	draw_rect(Rect2(-7, -20, 14, 9), Palette.TERRAIN_EDGE)
	draw_rect(Rect2(-7, -20, 14, 9), glow, false, 1.0)
	draw_line(Vector2(0, -18), Vector2(0, -15), glow, 1.5)
	draw_circle(Vector2(0, -13), 0.8, glow)
