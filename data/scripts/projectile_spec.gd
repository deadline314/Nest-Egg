class_name ProjectileSpec
extends Resource
## 子彈規格：玩家武器、敵人與頭目共用。
## source_id 會被敗北圖鑑用來判斷死因，請與 data/codex/defeat_cards.json 的 id 對應。

## Scene scale bounds keep accepted values far inside float32 vector arithmetic.
const MAX_SPEED_MULTIPLIER := 8.0
const MAX_VECTOR_COMPONENT := 1000000.0
const NUMERIC_LIMITS := {
	"speed": 10000.0, "gravity": 10000.0, "lifetime": 30.0, "knockback": 10000.0,
	"explosion_radius": 1024.0, "trail_distance": 40.0, "radius": 128.0,
	"length": 512.0, "trail_width": 64.0,
}
const INTEGER_LIMITS := {"damage": 10000, "stagger": 1000, "pierce": 512,
	"explosion_damage": 10000, "trail_points": 14}

@export var source_id: StringName = &""

@export_group("Motion")
@export var speed: float = 400.0
@export var gravity: float = 0.0
@export var lifetime: float = 1.0

@export_group("Damage")
@export var damage: int = 1
@export var stagger: int = 1
@export var knockback: float = 40.0
## 可貫穿的目標數量（0 = 命中即消失）。
@export var pierce: int = 0
@export var passes_walls: bool = false
@export var explosion_radius: float = 0.0
@export var explosion_damage: int = 0
@export var explode_on_expire: bool = false

@export_group("Visual")
## Shape is decorative; radius remains the shared physical head radius.
@export_enum("round", "rifle", "compact", "pellet", "energy", "rail", "grenade", "shell", "organic", "wave") var visual_style: String = "round"
## Maximum decorative trail in world pixels, independent of speed and frame rate.
@export_range(0.0, 40.0) var trail_distance: float = 14.0
@export var radius: float = 3.0
@export var length: float = 8.0
@export var color: Color = Color.WHITE
## 彈道拖尾：記錄最近幾個位置畫成漸細漸淡的尾巴（0＝沒有拖尾，上限見 Projectile.MAX_TRAIL_POINTS）；trail_width 是粗細倍率（細長的子彈用小一點）。
@export var trail_points: int = 5
@export var trail_width: float = 1.0
## 火箭類：飛行時每隔一小段冒一縷煙。
@export var smoke_trail: bool = false


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if source_id == &"":
		errors.append("source_id missing")
	errors.append_array(numeric_problems())
	if visual_style not in ["round", "rifle", "compact", "pellet", "energy", "rail", "grenade", "shell", "organic", "wave"]:
		errors.append("visual_style unknown style: " + visual_style)
	return errors


## Numeric checks are shared with direct pool callers; anonymous test/ability specs
## keep their legacy identity behavior while catalog resources require source_id.
func numeric_problems() -> PackedStringArray:
	var errors := PackedStringArray()
	var components := {"r": color.r, "g": color.g, "b": color.b, "a": color.a}
	for field: String in components:
		var value: float = components[field]
		var limit := 1.0 if field == "a" else 8.0
		if not is_finite(value) or value < 0.0 or value > limit:
			errors.append("color/%s outside finite 0–%s" % [field, limit])
	for field: String in NUMERIC_LIMITS:
		var value := float(get(field))
		if not is_finite(value) or value < 0.0 or value > float(NUMERIC_LIMITS[field]):
			errors.append("%s must be finite in 0–%s" % [field, NUMERIC_LIMITS[field]])
	if speed <= 0.0 or lifetime <= 0.0 or radius <= 0.0 or damage < 1:
		errors.append("speed/lifetime/radius/damage must be positive")
	for field: String in INTEGER_LIMITS:
		if int(get(field)) < 0 or int(get(field)) > int(INTEGER_LIMITS[field]):
			errors.append("%s outside 0–%s" % [field, INTEGER_LIMITS[field]])
	return errors


func spawn_problems(origin: Vector2, direction: Vector2, speed_multiplier: float) -> PackedStringArray:
	var errors := numeric_problems()
	for field: String in ["origin", "direction"]:
		var value: Vector2 = origin if field == "origin" else direction
		if not is_finite(value.x) or not is_finite(value.y) or absf(value.x) > MAX_VECTOR_COMPONENT or absf(value.y) > MAX_VECTOR_COMPONENT:
			errors.append("%s components must be finite within +/- %s" % [field, MAX_VECTOR_COMPONENT])
	if not is_finite(speed_multiplier) or speed_multiplier <= 0.0 or speed_multiplier > MAX_SPEED_MULTIPLIER:
		errors.append("speed_multiplier must be finite in (0,%s]" % MAX_SPEED_MULTIPLIER)
	return errors


func source_context() -> String:
	return resource_path if not resource_path.is_empty() else "ProjectileSpec %s" % source_id
