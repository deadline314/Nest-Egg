extends ScenarioBase
## NE-44 情境：把新增的七個骨架外觀擺進真正的關卡光影（法線、輪廓光、環境光補光），
## 一張在冷白的轉運站光影（頭頂一盞暖光燈，看法線與輪廓光）、一張在近乎全黑的停電光影（沒有燈，確認暗處仍然看得清楚）。

const LINEUP: Array[String] = ["old_k", "mei", "wataru", "reclaimer", "sniper", "flamer", "heavy_gunner"]
const WEAPONS := {
	"old_k": "pistol", "mei": "smg", "wataru": "", "reclaimer": "rifle", "sniper": "sniper", "flamer": "flamethrower", "heavy_gunner": "minigun",
}
## 關卡開場的章節標題卡淡出需要的時間。
const TITLE_CARD_TIME := 6.0
const LIGHTING := {"transfer": "res://data/lighting/transfer.tres", "blackout": "res://data/lighting/blackout.tres"}


func run() -> void:
	for tag: String in LIGHTING.keys():
		await open_arena(LIGHTING[tag], 20.0)
		var puppets: Array[_Puppet] = []
		for i in LINEUP.size():
			var puppet := _Puppet.new()
			puppet.position = Vector2((12.0 + i * 3.0) * 16.0, FLOOR_Y)
			level._entities.add_child(puppet)
			puppet.setup(LINEUP[i], str(WEAPONS[LINEUP[i]]))
			puppets.append(puppet)
		player.global_position = Vector2(8 * 16.0, FLOOR_Y)
		snap_camera()
		if tag == "transfer":
			var lamp := LightKit.create_point_light(Color(1.0, 0.85, 0.6), 170.0, 1.5, false)
			lamp.global_position = Vector2(27 * 16.0, FLOOR_Y - 64.0)
			level.add_child(lamp)
		await wait(TITLE_CARD_TIME)
		capture("NE-44-ingame-%s" % tag)
		await finish()


## 站在原地、望向右邊的角色（只負責驅動骨架動畫，不參與戰鬥）。
class _Puppet:
	extends Node2D
	var rig: CharacterRig
	var input := RigInput.new()

	func setup(skin: String, weapon: String) -> void:
		rig = CharacterRig.new()
		add_child(rig)
		rig.setup(skin)
		rig.set_weapon(weapon)
		input.aim_dir = Vector2(1, 0.05).normalized()
		input.on_floor = true

	func _process(delta: float) -> void:
		if rig != null:
			rig.animate(delta, input)
