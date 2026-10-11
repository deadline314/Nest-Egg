class_name BladeLight
extends Node2D
## 刃光（NE-260）：近戰武器的發光部位是真的光。拿在手上時照亮主角身邊一小圈，揮動時變亮變大、跟著刀刃走，
## 所以暗的區域裡揮一刀看得到被照亮的牆與敵人。每把武器的光（顏色、大小、亮度、揮動時放大幾倍、光在刀身的哪裡）
## 寫在 data/weapon_art/melee.json，顏色用武器資料的顏色；沒有設定的武器沒有刃光。
## 設定的「減少閃光」打開時，揮動的那一下不會突然變亮那麼多。
## 光登記在場景光源裡：受光源預算管理，也會讓被照到的敵人在牆上投影。

## 亮度追上目標的速度（每秒）：拿出來、收起來與揮動都是漸變。
const FADE := 9.0
## 揮動時光池半徑放大的上限（亮度照資料的倍數，半徑只放大這麼多，免得一揮整個畫面都亮）。
const SWING_RADIUS := 1.35

var _light: PointLight2D
var _level := 0.0
var _boost := 1.0
var _weapon_id: StringName = &""
var _base_radius := 0.0
var _base_energy := 0.0
var _swing_gain := 1.0
var _along := 0.0


func _ready() -> void:
	top_level = true
	_light = LightKit.create_point_light(Color.WHITE, 40.0, 0.0)
	_light.enabled = false
	add_child(_light)


## 每影格由主角的外觀呼叫：依手上有沒有近戰武器、正不正在揮，更新光的位置與亮度。
func follow(visual: PlayerVisual, delta: float) -> void:
	var holding := visual.shows_melee_weapon() and visual.is_visible_in_tree()
	var weapon := visual.player.loadout.active_weapon() if holding else null
	if weapon != null and weapon.id != _weapon_id:
		_configure(weapon)
	var active := weapon != null and _base_radius > 0.0
	if active:
		var hold := visual.melee_hold()
		global_position = hold.origin + hold.x * _along
	var swinging := active and visual.player.is_melee_swinging()
	var gain := 1.0 + (_swing_gain - 1.0) * Settings.flash_scale() if swinging else 1.0
	var blend := 1.0 - exp(-FADE * delta)
	_level = lerpf(_level, 1.0 if active else 0.0, blend)
	_boost = lerpf(_boost, gain, blend)
	if _level <= 0.01 and not active:
		if _light.enabled:
			_light.enabled = false
		return
	_light.enabled = true
	_light.energy = _base_energy * _level * _boost
	_light.texture_scale = maxf(0.05, _base_radius * minf(_boost, SWING_RADIUS) * 2.0 / LightKit.TEXTURE_SIZE)


## 現在的亮度（0＝沒有刃光）與光源（測試與量測用）。
func energy() -> float:
	return _light.energy if _light.enabled else 0.0


func light() -> PointLight2D:
	return _light


func _configure(weapon: WeaponData) -> void:
	_weapon_id = weapon.id
	var spec := MeleeArt.light_spec(weapon)
	_base_radius = float(spec.get("radius", 0.0))
	_base_energy = float(spec.get("energy", 0.0))
	_swing_gain = maxf(1.0, float(spec.get("swing", 1.0)))
	_along = float(spec.get("at", weapon.melee_length * 0.6))
	_light.color = weapon.color
