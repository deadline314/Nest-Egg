class_name PlayerFx
extends RefCounted
## 玩家身上的特效配方（格擋、完美反彈、衝刺、義體能力、重生）：全部只呼叫 Fx 的共用特效，數量與亮度吃 Fx 的三個克制係數，
## 不配置新節點。HDR 亮度一律走 Fx.hdr（有上限，不過曝）。

## 完美反彈：星芒、折射衝擊波、沿反彈方向的火花扇。
static func parry(at: Vector2, direction: Vector2) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	Fx.flare(at, Palette.WHITE, 34.0, 0.12)
	Fx.shock(at, 46.0, 0.03, Palette.CYAN, 0.3)
	Fx.sparks(at, Palette.CYAN, 10, 280.0, 0.3, dir, 1.3, 180.0)


## 一般格擋：盾面被打到的火花（朝來襲方向的反向噴出），比反彈小很多。
static func block(at: Vector2, incoming: Vector2) -> void:
	var back := -incoming.normalized() if incoming.length_squared() > 0.0001 else Vector2.UP
	Fx.sparks(at, Palette.WHITE, 5, 200.0, 0.2, back, 1.0, 260.0)


## 衝刺起步：身後拉出幾道速度線。
static func dash(from: Vector2, direction: Vector2) -> void:
	var back := Vector2(-signf(direction.x) if direction.x != 0.0 else -1.0, 0.0)
	Fx.sparks(from + Vector2(0.0, -22.0), Palette.CYAN, 5, 150.0, 0.18, back, 0.5, 0.0)


## 義體能力啟動：以身體為中心的衝擊波與星芒（顏色是能力的顏色）。
static func ability(center: Vector2, color: Color, radius: float) -> void:
	Fx.flare(center, color, clampf(radius * 0.4, 24.0, 60.0), 0.14)
	Fx.shock(center, clampf(radius * 0.5, 30.0, 90.0), 0.025, color, 0.35)


## 重生：腳下的光環與向上飄的餘燼，配合 PlayerVisual 的淡入。
static func respawn(feet: Vector2) -> void:
	Fx.shock(feet + Vector2(0.0, -4.0), 38.0, 0.02, Palette.CYAN, 0.5)
	Fx.embers(feet, Palette.CYAN, 12, 60.0, 0.9, 12.0)
	Fx.flash_light(feet + Vector2(0.0, -22.0), Palette.CYAN, 90.0, 1.6, 0.5)
