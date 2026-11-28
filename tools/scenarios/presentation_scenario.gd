extends ScenarioBase
## 章節與地點的呈現：進入章節第一個區域、穿過出入口進新區域、回訪、章末，各拍淡入、停留、淡出三格。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=presentation [--tag=before]
## 檔名前綴預設 after；拍修前畫面時加 --tag=before。

const SLOW := 0.15
const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const STREET := "res://data/levels/ch1_street.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"

var prefix := "after"


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			prefix = arg.trim_prefix("--tag=")
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	Settings.set_ui_text_scale(1.0)
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	# 第一章的開頭：從當舖進場（章節的第一個區域）。
	await _enter(PAWNSHOP, &"")
	await _capture_moment("chapter-start")
	# 穿過出入口進入新的地點（亮的街道）。
	await _enter(STREET, &"street_home")
	await _capture_moment("area-bright")
	# 暗的室內：碼頭倉庫。
	await _enter(WAREHOUSE, &"wh_street")
	await _capture_moment("area-dark")
	# 回訪：再回到街道。
	await _enter(STREET, &"street_home")
	await _capture_moment("area-revisit")
	await _chapter_end()
	await _scaled_text()
	await _pause_menu()
	await _main_menu()
	await finish()


func _enter(path: String, portal: StringName) -> void:
	if is_instance_valid(level):
		level.queue_free()
		await settle(3)
	if portal != &"":
		GameState.pending_portal = portal
	level = Level.new()
	level.configure(load(path))
	add_child(level)
	await settle(4)
	player = level.player


## 找到這次進場的呈現節點（修前是章節卡或中央橫幅；修後是地點標示），各拍淡入一半、停留、淡出一半。
func _capture_moment(tag: String) -> void:
	var node: Node = null
	for i in 600:
		node = _presentation_node()
		if node != null and _alpha(node) > 0.02:
			break
		await get_tree().process_frame
	if node == null:
		print("PRESENTATION %s: nothing shown" % tag)
		capture("%s-%s-none" % [prefix, tag])
		return
	Engine.time_scale = SLOW
	for i in 600:
		if not is_instance_valid(node) or _alpha(node) >= 0.5:
			break
		await get_tree().process_frame
	capture("%s-%s-0-in" % [prefix, tag])
	for i in 900:
		if not is_instance_valid(node) or _alpha(node) >= 0.99:
			break
		await get_tree().process_frame
	# 第二行、印這些較晚出現的部分也要到位再拍停留。
	await wait(1.3 if node is ChapterCard else 0.45)
	capture("%s-%s-1-hold" % [prefix, tag])
	var seen_full := false
	for i in 6000:
		if not is_instance_valid(node):
			break
		var a := _alpha(node)
		if a >= 0.99:
			seen_full = true
		elif seen_full and a <= 0.5:
			break
		await get_tree().process_frame
	capture("%s-%s-2-out" % [prefix, tag])
	Engine.time_scale = 1.0
	print("PRESENTATION %s node=%s" % [tag, node.get_class() if is_instance_valid(node) else "freed"])
	await wait(1.5)


func _presentation_node() -> Node:
	for node in level.find_children("*", "", true, false):
		if node is ChapterCard or (node.has_method(&"presentation_alpha")):
			return node
	var banner: UiBanner = level.hud.toast_banner if level.hud != null else null
	if banner != null and banner.is_showing():
		return banner
	return null


func _alpha(node: Node) -> float:
	if node.has_method(&"presentation_alpha"):
		return node.call(&"presentation_alpha")
	if node is ChapterCard:
		return (node.get("_root") as Control).modulate.a
	return (node as CanvasItem).modulate.a


func _chapter_end() -> void:
	var info := Story.chapter_info(&"ch1_kasa")
	var card: Node = level._end_card(info) if level.has_method(&"_end_card") else level._show_chapter_card(str(info["end_title"]), str(info.get("teaser", "")), true, 2.8)
	await settle(2)
	await _capture_moment("chapter-end")
	if is_instance_valid(card):
		card.queue_free()
		await settle(3)
	get_tree().paused = false


## 文字放大 1.2 倍：地點標示（第一次到訪的完整版）與章末畫面停留時各拍一張。
func _scaled_text() -> void:
	Settings.set_ui_text_scale(1.2)
	await settle(2)
	var marker := LocationMarker.for_level(load(PAWNSHOP), Story.language, false)
	level.add_child(marker)
	await wait(1.2)
	capture("%s-scale12-marker" % prefix)
	print("PRESENTATION scale12 marker rect=%s view=%s" % [marker.screen_rect(), get_viewport().get_visible_rect().size])
	marker.queue_free()
	var card := level._end_card(Story.chapter_info(&"ch1_kasa")) if level.has_method(&"_end_card") else null
	if card != null:
		await wait(2.6)
		capture("%s-scale12-end" % prefix)
		card.queue_free()
		await settle(3)
	get_tree().paused = false
	Settings.set_ui_text_scale(1.0)
	await settle(2)


func _pause_menu() -> void:
	level._pause_menu.open()
	await wait(0.6)
	capture("%s-pause" % prefix)
	level._pause_menu.close()
	await settle(3)


func _main_menu() -> void:
	level.queue_free()
	level = null
	await settle(3)
	var menu := MainMenu.new()
	menu.continue_available = true
	if "continue_level" in menu:
		menu.set("continue_level", STREET)
	add_child(menu)
	await wait(1.2)
	capture("%s-main-menu" % prefix)
	menu.queue_free()
	await settle(3)
