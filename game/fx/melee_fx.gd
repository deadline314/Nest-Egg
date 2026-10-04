class_name MeleeFx
extends RefCounted
## 近戰的特效配方（命中、揮擊瞬間、終結技）：依招式資料的 impact_fx 分三種——
## slash 斬擊（火花與小星芒）、pierce 刺擊（細長的火花）、crush 重擊（塵土、衝擊波與較大的火花）。
## 全部只呼叫 Fx 的共用特效，數量與亮度吃 Fx 的克制係數，不配置新節點。

const KINDS: PackedStringArray = ["slash", "pierce", "crush"]


## 命中：at 是命中位置，direction 是揮擊方向，heavy 是重擊（硬直以上）。
static func hit(at: Vector2, direction: Vector2, color: Color, kind: StringName, heavy: bool) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	match kind:
		&"crush":
			Fx.dust(at + Vector2(0.0, 18.0), 5, 36.0)
			Fx.shock(at, 40.0 if heavy else 26.0, 0.03, color, 0.3)
			Fx.sparks(at, color, 8, 260.0, 0.3, dir, 1.5, 320.0)
			Fx.flare(at, color, 26.0, 0.09)
		&"pierce":
			Fx.sparks(at, color, 6, 340.0, 0.22, dir, 0.6, 80.0)
			Fx.flare(at, color, 16.0, 0.07)
		_:
			Fx.sparks(at, color, 7, 260.0, 0.25, dir, 1.7, 260.0)
			Fx.flare(at, color, 22.0 if heavy else 15.0, 0.08)


## 揮擊的瞬間（命中與否都會播）：鞭子甩到頂端的爆響、重武器砸地的塵土。origin 是身體中心、feet 是腳底。
static func swing(origin: Vector2, feet: Vector2, direction: Vector2, reach: float, color: Color, kind: StringName, lash: bool) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	if lash:
		var tip := origin + dir * reach
		Fx.flare(tip, color, 20.0, 0.09)
		Fx.sparks(tip, color, 4, 200.0, 0.2, dir, 1.0, 0.0)
	elif kind == &"crush":
		Fx.dust(feet + Vector2(dir.x * reach * 0.7, 0.0), 4, 30.0)


## 終結技：目標身上交叉的兩道斬痕、星芒與衝擊波。
static func finisher(target: Vector2, color: Color) -> void:
	Fx.arc(target + Vector2(-16.0, -14.0), target + Vector2(16.0, 14.0), Fx.hdr(Palette.WHITE, 2.0), 0.14, 1.8, 0.02, 0)
	Fx.arc(target + Vector2(16.0, -14.0), target + Vector2(-16.0, 14.0), Fx.hdr(color, 2.0), 0.14, 1.8, 0.02, 0)
	Fx.flare(target, Palette.WHITE, 36.0, 0.12)
	Fx.shock(target, 52.0, 0.035, color, 0.35)
	Fx.sparks(target, color, 10, 300.0, 0.3)
