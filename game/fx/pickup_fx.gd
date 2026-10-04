class_name PickupFx
extends RefCounted
## 拾取特效：依道具類型各有一種收進身體的感覺——
## weapon 武器（星芒、衝擊波、火花扇）、heal 補給（向上飄的光點）、credit 信用點（往上彈的金色火花）、
## item 消耗品（小衝擊波與火花）、story 劇情道具（慢慢擴散的光環與餘燼）。數量與亮度吃 Fx 的克制係數，不配置新節點。

const KINDS: PackedStringArray = ["weapon", "heal", "credit", "item", "story"]


static func collect(at: Vector2, color: Color, kind: StringName) -> void:
	match kind:
		&"weapon":
			Fx.flare(at, Palette.WHITE, 34.0, 0.12)
			Fx.shock(at, 36.0, 0.025, color, 0.35)
			Fx.sparks(at, color, 9, 240.0, 0.35, Vector2.UP, 2.4, 260.0)
			Fx.flash_light(at, color, 80.0, 1.6, 0.3)
		&"heal":
			Fx.embers(at, color, 8, 40.0, 0.9, 6.0)
			Fx.flare(at, color, 24.0, 0.12)
			Fx.flash_light(at, color, 70.0, 1.2, 0.3)
		&"credit":
			Fx.sparks(at, color, 6, 160.0, 0.4, Vector2.UP, 1.6, 520.0)
			Fx.flare(at, color, 14.0, 0.08)
			Fx.flash_light(at, color, 44.0, 0.9, 0.2)
		&"story":
			Fx.shock(at, 44.0, 0.02, color, 0.6)
			Fx.embers(at, color, 10, 30.0, 1.2, 8.0)
			Fx.flash_light(at, color, 90.0, 1.4, 0.45)
		_:
			Fx.shock(at, 26.0, 0.02, color, 0.3)
			Fx.sparks(at, color, 7, 200.0, 0.3, Vector2.UP, 2.0, 260.0)
			Fx.flash_light(at, color, 60.0, 1.2, 0.25)
