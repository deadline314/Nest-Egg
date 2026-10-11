class_name WeaponData
extends Resource
## 武器定義。新增武器只需建立新的 .tres，不必改程式。

## Corruption bounds, not balance targets. Every shipped resource remains unchanged.
const MAX_PELLETS := 64
const MAX_AMMO := 10000
const MIN_FIRE_INTERVAL := 0.01
const NUMERIC_LIMITS := {
	"fire_interval": 30.0, "reload_time": 120.0, "spread_degrees": 360.0,
	"random_spread_degrees": 360.0, "melee_length": 512.0, "screen_shake": 100.0,
	"camera_kick": 512.0, "recoil": 10000.0, "muzzle_light_energy": 32.0,
	"muzzle_flare_size": 512.0, "muzzle_light_radius": 2048.0, "muzzle_fx_interval": 30.0,
	"screen_shake_time": 5.0, "bloom_per_shot": 1.0,
}

@export var id: StringName = &"weapon"
@export var display_name: String = "武器"
@export var color: Color = Color.WHITE
@export var projectile: ProjectileSpec
@export var fire_interval: float = 0.15
## 彈匣容量；0 代表沒有彈匣、不需換彈（例如機甲加農砲）。
@export var magazine_size: int = 0
## 備彈上限；-1 代表無限。
@export var max_reserve: int = -1
## 換彈所需秒數。
@export var reload_time: float = 1.2
@export var ammo_per_shot: int = 1
@export var pellets: int = 1
@export var spread_degrees: float = 0.0
@export var random_spread_degrees: float = 0.0
## 能量武器（光束、電磁砲）：不拋彈殼，換彈稱為「換電池」。其餘為實彈武器。
@export var is_energy: bool = false
## 一句話說明，用於拾取提示與 HUD tooltip（講重點）。
@export var description: String = ""

@export_group("Melee")
## 近戰武器：非空字串代表這是近戰武器，值是 data/melee/<id>.json 的檔名（招式組：前搖、出招、後搖、判定、傷害…）。空字串＝槍械。
## 近戰武器沿用彈匣欄位當「電量」：magazine_size 是揮擊次數、ammo_per_shot 是每揮消耗、reload_time 是充電秒數；magazine_size = 0 不消耗。
@export var melee_profile: String = ""
## 武器的外型（程式繪製，見 MeleeArt）：blade 刃、heavy 重錘、polearm 長柄、whip 鞭；長度是像素。
@export_enum("blade", "heavy", "polearm", "whip") var melee_shape: String = "blade"
@export var melee_length: float = 18.0

@export_group("Light")
## 槍燈：掛在槍上的常亮照明，從槍口朝瞄準方向照出去。light_range 是照射距離（像素，0＝這把武器沒有槍燈）。
@export_range(0.0, 480.0, 5.0) var light_range: float = 0.0
## 光錐的張角（度）：越小越集中。
@export_range(4.0, 120.0, 1.0) var light_cone_degrees: float = 40.0
@export_range(0.0, 3.0, 0.05) var light_energy: float = 1.0
@export var light_color: Color = Color(1.0, 0.95, 0.85)
## 開火時光錐抖動的程度（0＝不抖，1＝最明顯）；設定的「減少閃光」會把它降下來。
@export_range(0.0, 1.0, 0.05) var light_jitter: float = 0.0
## 另外畫一條常亮的細瞄準光（光束類武器用）。
@export var light_sight: bool = false
## 開火後光先變暗，等到可以再開火時恢復全亮（射速慢的武器用，看光就知道下一發好了沒）。
@export var light_dims_until_ready: bool = false
@export_group("Feel")
@export var fire_sound: StringName = &"shot_rifle"
@export var screen_shake: float = 0.0
## 鏡頭往射擊反方向的位移量（像素），增加開槍的力道感。
@export var camera_kick: float = 1.5
## 後座力（像素／秒）：空中全額、地面 30%。
@export var recoil: float = 0.0
@export var muzzle_light_energy: float = 1.2
## 槍口閃光大小（像素）、火花數量、光的範圍；重武器大、輕武器小。
@export var muzzle_flare_size: float = 15.0
@export var muzzle_spark_count: int = 3
@export var muzzle_light_radius: float = 56.0
## 槍口特效（閃光、火花、光）的最短間隔秒數：連發武器每隔一下才播，避免粒子與光爆量；0 = 每發都播。
@export var muzzle_fx_interval: float = 0.0
## 鏡頭震動的持續秒數。
@export var screen_shake_time: float = 0.08
@export var ejects_casing: bool = true
## 每發增加的準星擴散（0~1）。連射越久越不準，首發永遠精準。
@export var bloom_per_shot: float = 0.15
## HUD 與武器欄顯示的簡短代號。
@export var short_name: String = ""
## 彈種圖示 id（art/ammo/<id>.png）：HUD、背包用來顯示這把武器的子彈。留空時依武器類型使用預設圖示。
@export var ammo_icon: StringName = &""
## 角色手上武器的外觀（art/weapons/weapons.json 的 id）。
@export var visual_id: String = "rifle"


func has_magazine() -> bool:
	return magazine_size > 0


func has_infinite_reserve() -> bool:
	return max_reserve < 0


func is_melee() -> bool:
	return not melee_profile.is_empty()


## 這把武器有沒有槍燈（近戰武器沒有）。
func has_light() -> bool:
	return light_range > 0.0 and not is_melee()


func is_valid() -> bool:
	return numeric_problems().is_empty() and (is_melee() or (projectile != null and projectile.validate().is_empty()))


## Catalog validation adds identity/profile checks to the runtime numeric guard.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"" or display_name.strip_edges().is_empty():
		errors.append("id/display_name must name a weapon")
	errors.append_array(numeric_problems())
	if not Sfx.has_named(fire_sound):
		errors.append("fire_sound unknown sound: " + str(fire_sound))
	if is_melee():
		if melee_profile != melee_profile.get_file() or melee_profile in [".", ".."] or melee_profile.contains(":") or melee_profile.contains("\\"):
			errors.append("melee_profile must name a local profile")
		if melee_shape not in ["blade", "heavy", "polearm", "whip"] or melee_length <= 0.0:
			errors.append("melee_shape/melee_length invalid")
	elif projectile == null:
		errors.append("projectile missing")
	else:
		for problem in projectile.validate():
			errors.append("projectile " + problem)
	return errors


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
	if fire_interval < MIN_FIRE_INTERVAL:
		errors.append("fire_interval below minimum %s" % MIN_FIRE_INTERVAL)
	for field: String in ["magazine_size", "ammo_per_shot"]:
		if int(get(field)) < 0 or int(get(field)) > MAX_AMMO:
			errors.append("%s outside 0–%s" % [field, MAX_AMMO])
	if max_reserve < -1 or max_reserve > MAX_AMMO:
		errors.append("max_reserve outside -1–%s" % MAX_AMMO)
	if ammo_per_shot < 1 or (has_magazine() and ammo_per_shot > magazine_size):
		errors.append("ammo_per_shot invalid for magazine_size")
	if pellets < 1 or pellets > MAX_PELLETS:
		errors.append("pellets outside 1–%s" % MAX_PELLETS)
	if muzzle_spark_count < 0 or muzzle_spark_count > 80:
		errors.append("muzzle_spark_count outside 0–80")
	return errors
