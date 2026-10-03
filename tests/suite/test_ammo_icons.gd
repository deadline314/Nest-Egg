class_name AmmoIconsSuite
extends TestSuite
## 彈種圖示（NE-41）：每把武器有專屬圖示、三種狀態、缺圖容錯、背包與 HUD 使用。
## 缺圖測試用的圖示 id 含 test_missing_ammo，執行器會忽略它的錯誤輸出。


func run() -> void:
	_test_icons_exist()
	_test_weapons_have_icons()
	_test_missing_icon()
	await _test_weapon_bar()
	await _test_inventory_entry()


func _test_icons_exist() -> void:
	var ids := AmmoIconPainter.CATALOG.map(func(spec: Dictionary) -> String: return str(spec["id"]))
	check(ids.size() >= 8, "彈種圖示至少 8 種（%d）" % ids.size())
	for id in ids:
		for state in [AmmoIcons.State.FULL, AmmoIcons.State.EMPTY, AmmoIcons.State.LOW]:
			var path := AmmoIcons.path_of(StringName(id), state)
			check(ResourceLoader.exists(path), "圖示存在：%s" % path)
			var tex := load(path) as Texture2D
			check(tex != null and Vector2i(tex.get_size()) == AmmoIcons.TEXTURE_SIZE, "圖示 %s 是 40×56（4 倍解析度）" % path.get_file())
		var full := (load(AmmoIcons.path_of(StringName(id), AmmoIcons.State.FULL)) as Texture2D).get_image()
		var empty := (load(AmmoIcons.path_of(StringName(id), AmmoIcons.State.EMPTY)) as Texture2D).get_image()
		var low := (load(AmmoIcons.path_of(StringName(id), AmmoIcons.State.LOW)) as Texture2D).get_image()
		check(full.get_data() != empty.get_data() and full.get_data() != low.get_data(), "圖示 %s 三種狀態的畫面不同" % id)


func _test_weapons_have_icons() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for file in DirAccess.get_files_at("res://data/weapons"):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/" + file) as WeaponData
		check(weapon.ammo_icon != &"", "武器 %s 指定了彈種圖示" % weapon.id)
		check(AmmoIcons.has_icon(weapon.ammo_icon), "武器 %s 的圖示 %s 存在" % [weapon.id, weapon.ammo_icon])
		seen[weapon.ammo_icon] = true
	check(seen.size() >= 7, "各武器使用不同的彈種圖示（%d 種）" % seen.size())
	var energy := WeaponData.new()
	energy.is_energy = true
	check(AmmoIcons.icon_id_for(energy) == AmmoIcons.DEFAULT_ENERGY, "沒指定圖示的能量武器用電池")
	check(AmmoIcons.icon_id_for(WeaponData.new()) == AmmoIcons.DEFAULT_ACTION, "沒指定圖示的實彈武器用手槍彈")
	check(AmmoIcons.icon_id_for(null) == AmmoIcons.DEFAULT_ACTION, "沒有武器時不會崩潰")


func _test_missing_icon() -> void:
	var tex := AmmoIcons.texture(&"test_missing_ammo")
	check(tex != null and Vector2i(tex.get_size()) == AmmoIcons.TEXTURE_SIZE, "缺圖時回傳同尺寸替代圖")
	check(not AmmoIcons.has_icon(&"test_missing_ammo"), "缺圖的圖示被標示為不存在")


func _test_weapon_bar() -> void:
	var level := await start_level(PropsSuite.level_data())
	var bar := level.hud.weapon_bar
	check(bar != null and bar.row_count() == Loadout.MAX_SLOTS, "HUD 武器欄每個欄位一列")
	var loadout := level.player.loadout
	check(bar.row_state(loadout.active_slot) == AmmoIcons.State.FULL, "滿匣時圖示是滿的")
	var slot := loadout.active_slot
	var weapon := loadout.weapon_in(slot)
	if weapon != null and weapon.has_magazine():
		loadout._mag[slot] = 1
		EventBus.player_loadout_changed.emit(loadout)
		check(bar.row_state(slot) == AmmoIcons.State.LOW, "彈量不到四分之一時圖示變成低量")
		loadout._mag[slot] = 0
		EventBus.player_loadout_changed.emit(loadout)
		check(bar.row_state(slot) == AmmoIcons.State.EMPTY, "空匣時圖示變成空槽")
	await end_level(level)


func _test_inventory_entry() -> void:
	var level := await start_level(PropsSuite.level_data())
	var page := WeaponsPage.new()
	page.context = InventoryContext.new(level.player)
	var entries := page._build_entries()
	var with_icon := 0
	for entry in entries:
		if entry.ammo_icon != null:
			with_icon += 1
	check(with_icon >= 1, "背包武器頁的卡片帶彈種圖示")
	page.free()
	await end_level(level)
