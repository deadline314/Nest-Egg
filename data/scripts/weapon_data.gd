class_name WeaponData
extends Resource
## 武器定義。新增武器只需建立新的 .tres，不必改程式。

@export var id: StringName = &"weapon"
@export var display_name: String = "武器"
@export var color: Color = Color.WHITE
@export var projectile: ProjectileSpec
@export var fire_interval: float = 0.15
## -1 代表無限彈藥。
@export var max_ammo: int = -1
@export var ammo_per_shot: int = 1
@export var pellets: int = 1
@export var spread_degrees: float = 0.0
@export var random_spread_degrees: float = 0.0
## 能量武器（光束、電磁砲）：不拋彈殼，換彈稱為「換電池」。其餘為實彈武器。
@export var is_energy: bool = false
## 一句話說明，用於拾取提示與 HUD tooltip（講重點）。
@export var description: String = ""

@export_group("Feel")
@export var fire_sound: StringName = &"shot_rifle"
@export var screen_shake: float = 0.0
## 鏡頭往射擊反方向的位移量（像素），增加開槍的力道感。
@export var camera_kick: float = 1.5
## 後座力（像素／秒）：空中全額、地面 30%。
@export var recoil: float = 0.0
@export var muzzle_light_energy: float = 1.2
@export var ejects_casing: bool = true
## 每發增加的準星擴散（0~1）。連射越久越不準，首發永遠精準。
@export var bloom_per_shot: float = 0.15
## HUD 與武器欄顯示的簡短代號。
@export var short_name: String = ""
## 角色手上武器的外觀（art/weapons/weapons.json 的 id）。
@export var visual_id: String = "rifle"


func has_infinite_ammo() -> bool:
	return max_ammo < 0


func is_valid() -> bool:
	return projectile != null and fire_interval > 0.0
