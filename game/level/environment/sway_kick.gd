class_name SwayKick
extends Area2D
## 會搖的擺設被帶動（BG-64）：玩家或敵人穿過、附近有爆炸時，往受力方向多擺一下再回彈停下。
## 掛在 PropNode 底下（只有資料裡 sway > 0 的擺設才有）。原本的風吹由搖動著色器負責，這裡只多加一段位移
## （著色器的每實體參數 kick），所以同設定的擺設仍共用同一份材質。
## 用有阻尼的彈簧回彈；靜止時不跑每影格更新。擺設沒有碰撞形狀以外的作用：不擋子彈、不影響任何判定。
## 「減少動態」開啟時不加這段位移。

const GROUP := &"sway_kick"
const KICK_PARAM := &"kick"
## 彈簧：回彈的快慢（每秒弧度）與阻尼比（小於 1 會來回擺幾下再停）。
const FREQUENCY := 9.0
const DAMPING := 0.28
## 角色以這個速度（像素／秒）穿過時給滿一次推力；走路大約三分之一、衝刺超過就夾在上限。
const FULL_SPEED := 420.0
## 滿推力時擺動端的位移，是擺設本身風吹幅度的幾倍；以及位移的像素上限與下限（風吹很小的擺設也看得出被碰到）。
const PUSH_SCALE := 4.5
const MIN_PUSH := 3.0
const MAX_OFFSET := 12.0
## 爆炸的影響範圍是爆炸半徑的幾倍，以及滿強度時是幾倍的滿推力。
const BLAST_REACH := 3.0
const BLAST_SCALE := 1.6
## 位移與速度都小於這個值就算停下。
const REST_OFFSET := 0.05
const REST_SPEED := 1.0

var _targets: Array[CanvasItem] = []
var _push := MIN_PUSH
var _offset := 0.0
var _velocity := 0.0


## 掛到會搖的擺設上。targets 是套了搖動材質的圖（本體與自發光層），area 是擺設的範圍（本地座標），
## amplitude 是擺設資料的風吹幅度。資料不合理時不建立並回傳 null，擺設照常只有風吹。
static func attach(prop: Node2D, targets: Array[CanvasItem], area: Rect2, amplitude: float) -> SwayKick:
	if prop == null or targets.is_empty() or not is_finite(amplitude) or amplitude <= 0.0 \
			or not area.size.is_finite() or area.size.x <= 0.0 or area.size.y <= 0.0:
		push_warning("[SwayKick] %s 的搖動資料無效，只保留原本的風吹" % (prop.name if prop != null else &"（沒有擺設）"))
		return null
	var kick := SwayKick.new()
	kick.name = "SwayKick"
	kick._targets = targets
	kick._push = clampf(amplitude * PUSH_SCALE, MIN_PUSH, MAX_OFFSET)
	var shape := RectangleShape2D.new()
	shape.size = area.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = area.get_center()
	kick.add_child(collision)
	prop.add_child(kick)
	return kick


func _init() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER | Layers.ENEMY
	monitorable = false
	input_pickable = false


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)  # 靜止時不處理；被推到才開始（進場時引擎會自動開啟，所以在這裡關）
	body_entered.connect(_on_body_entered)


## 目前多擺出去的位移（像素；測試與量測用）。
func offset() -> float:
	return _offset


func is_resting() -> bool:
	return not is_processing()


func _on_body_entered(body: Node2D) -> void:
	var mover := body as CharacterBody2D
	if mover != null:
		push(mover.velocity.x / FULL_SPEED)


## 給一次推力：strength 是滿推力的倍數，正值往右。連續觸發會疊加，但位移永遠夾在上限內。
func push(strength: float) -> void:
	if not is_finite(strength) or is_zero_approx(strength) or Settings.get_reduce_ui_motion():
		return
	# 推力換成初速：無阻尼時位移的峰值會剛好是 strength × _push。
	_velocity = clampf(_velocity + strength * _push * FREQUENCY, -MAX_OFFSET * FREQUENCY, MAX_OFFSET * FREQUENCY)
	set_process(true)


## 爆炸（Fx.explosion 對整個群組呼叫）：範圍內的擺設往遠離爆炸的方向擺，越近越大。
func blast(world_position: Vector2, radius: float) -> void:
	var reach := radius * BLAST_REACH
	if reach <= 0.0:
		return
	var away := global_position + _center() - world_position
	var distance := away.length()
	if distance >= reach:
		return
	var direction := signf(away.x) if absf(away.x) > 1.0 else 1.0
	push(direction * BLAST_SCALE * (1.0 - distance / reach))


func _center() -> Vector2:
	var collision := get_child(0) as CollisionShape2D if get_child_count() > 0 else null
	return collision.position if collision != null else Vector2.ZERO


func _process(delta: float) -> void:
	# 有阻尼的彈簧（半隱式積分，影格時間再長也不會發散）。
	var step := minf(delta, 1.0 / 30.0)
	_velocity += (-FREQUENCY * FREQUENCY * _offset - 2.0 * DAMPING * FREQUENCY * _velocity) * step
	_offset = clampf(_offset + _velocity * step, -MAX_OFFSET, MAX_OFFSET)
	if absf(_offset) < REST_OFFSET and absf(_velocity) < REST_SPEED:
		_offset = 0.0
		_velocity = 0.0
		set_process(false)
	_apply()


func _apply() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.set_instance_shader_parameter(KICK_PARAM, _offset)
