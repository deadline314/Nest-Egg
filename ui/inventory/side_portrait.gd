class_name SidePortrait
extends Control
## 背包右側陪伴閱讀的角色（NE-244、NE-393）：把遊戲內同一個角色骨架以高倍率畫出來（HdPortrait），所以外觀和玩家操作的
## 主角永遠一致，並且會呼吸、眨眼、換重心、偶爾做小動作（撥頭髮、思考）。腳底貼齊下緣、依可用高度等比縮放，
## 後方一道冷青背光、腳下一條接觸影。受損外觀跟著主角的生命比例。
## 只在背包開著時持有角色（acquire／release），關閉就放掉，開關多次也只有一份。骨架找不到時記錄並留白，不影響清單與操作。

const CHARACTER := "rin"
## 角色站立時的寬 ÷ 高（含頭髮與外套的擺動範圍）：決定角色在欄位裡佔的範圍。
const ASPECT := 0.42
## 背光與接觸影（HDR 2D 在線性色彩混色，透明度要比感覺低）。背光是放射漸層，中心最亮、往外淡到透明。
const GLOW := Color(0.25, 0.85, 0.95, 0.22)
const SHADOW := Color(0.0, 0.0, 0.0, 0.45)
## 背光相對角色的大小（寬、高倍率）與中心高度（從頭頂算起的比例）。
const GLOW_SCALE := Vector2(1.5, 0.9)
const GLOW_CENTER := 0.42

static var _glow: GradientTexture2D

## 面向（-1＝朝左，看著清單）。
var facing := -1

var _figure: HdPortrait
var _health_ratio := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_figure)
	EventBus.player_health_changed.connect(_on_player_health_changed)
	if _glow == null:
		# 共用一張 64×64 的小漸層，所有背包畫面都畫同一張。
		var gradient := Gradient.new()
		gradient.set_color(0, GLOW)
		gradient.set_color(1, Color(GLOW, 0.0))
		gradient.add_point(0.55, Color(GLOW, GLOW.a * 0.35))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64


## 背包開啟時呼叫。重複呼叫不會多建一份。
func acquire() -> void:
	if _figure != null:
		return
	_figure = HdPortrait.new()
	_figure.name = "Figure"
	_figure.character = CHARACTER
	_figure.facing = facing
	add_child(_figure)
	if not _figure.has_rig():
		# 找不到骨架時 HdPortrait 已經記錄是哪個角色；這裡留白。
		_figure.queue_free()
		_figure = null
	else:
		_figure.set_health_ratio(_health_ratio)
		_layout_figure()
	queue_redraw()


## 背包關閉時呼叫：放掉角色與它的子視窗，下次開啟再建（貼圖在引擎的資源快取裡，重開不必重新解碼）。
func release() -> void:
	if _figure != null:
		_figure.queue_free()
		_figure = null
	queue_redraw()


## 目前有沒有持有角色（背包開著才有）。
func has_texture() -> bool:
	return _figure != null


## 讓角色做一個指定的小動作（測試與截圖用）。
func play_gesture(gesture_name: StringName) -> bool:
	return _figure != null and _figure.play_gesture(gesture_name)


## 角色實際畫在哪裡（控制項座標）；測試用它確認不壓到文字與按鈕。
func drawn_rect() -> Rect2:
	if _figure == null or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var height := minf(size.y, size.x / ASPECT)
	var drawn := Vector2(height * ASPECT, height)
	return Rect2(Vector2((size.x - drawn.x) * 0.5, size.y - drawn.y), drawn)


func _layout_figure() -> void:
	if _figure != null:
		var rect := drawn_rect()
		_figure.position = rect.position
		_figure.size = rect.size
	queue_redraw()


func _on_player_health_changed(current: int, maximum: int) -> void:
	_health_ratio = float(current) / float(maximum) if maximum > 0 else 1.0
	if _figure != null:
		_figure.set_health_ratio(_health_ratio)


func _draw() -> void:
	var rect := drawn_rect()
	if not rect.has_area():
		return
	var center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * GLOW_CENTER)
	var glow_size := Vector2(rect.size.x * GLOW_SCALE.x * 1.4, rect.size.y * GLOW_SCALE.y)
	draw_texture_rect(_glow, Rect2(center - glow_size * 0.5, glow_size), false)
	draw_set_transform(Vector2(rect.get_center().x, rect.end.y - 2.0), 0.0, Vector2(1.0, 0.18))
	draw_circle(Vector2.ZERO, rect.size.x * 0.42, SHADOW)
	draw_set_transform(Vector2.ZERO)
