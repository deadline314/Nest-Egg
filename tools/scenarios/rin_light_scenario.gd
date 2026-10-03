extends ScenarioBase
## NE-71 情境：凜在三種代表性光影下的樣子（轉運站的冷白光、停電的近乎全黑、霓虹市集的彩色光），
## 不加任何額外燈光、不畫輔助框，確認法線（輪廓光）、發光層與暗處的可讀性。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=rin_light

const LIGHTING := {
	"transfer": "res://data/lighting/transfer.tres",
	"blackout": "res://data/lighting/blackout.tres",
	"market": "res://data/lighting/market.tres",
}


func run() -> void:
	for tag: String in LIGHTING.keys():
		await open_arena(LIGHTING[tag], 18.0)
		player.health.setup(999, 0.0)
		var trooper := spawn_enemy("res://data/enemies/grunt.tres", 21.0)
		trooper.process_mode = Node.PROCESS_MODE_DISABLED
		place_player(18.0)
		await wait(1.2)
		var screen := get_viewport().get_canvas_transform() * (player.aim_origin() + Vector2(90, -6))
		Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))
		await wait(0.5)
		capture("rin_light_%s" % tag)
		await finish()
