extends Node
## Inventory actual pickup cells in every currently implemented LevelData.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var report := {"levels": [], "total_by_key": {}, "missing": []}
	for file in DirAccess.get_files_at("res://data/levels"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/levels/" + file) as LevelData
		if data == null:
			continue
		var layout := LevelBuilder.parse(data)
		var counts := {}
		if not layout.health_pickups.is_empty():
			counts["repair_pack"] = layout.health_pickups.size()
		for spawn in layout.spawns:
			var resource: Resource = spawn["resource"]
			var key := ""
			if resource is WeaponData:
				var pickup := WeaponPickup.new()
				pickup.configure(resource)
				key = pickup.world_icon_key()
				pickup.free()
			elif resource is ConsumableData:
				key = resource.icon
			elif resource is StoryItemData and (resource.is_collectible() or resource.trigger == StoryItemData.Trigger.MANUAL):
				key = resource.icon
			elif resource is CreditPileData:
				key = "credits_large" if resource.value >= 30 else "credits_small"
			if not key.is_empty():
				counts[key] = int(counts.get(key, 0)) + 1
		for key: String in counts:
			report["total_by_key"][key] = int(report["total_by_key"].get(key, 0)) + counts[key]
			if ItemIcons.world(key).is_empty():
				report["missing"].append({"level": str(data.id), "key": key})
		report["levels"].append({"level": str(data.id), "map": data.layout_path, "counts": counts})
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var stream := FileAccess.open(output, FileAccess.WRITE)
		if stream == null:
			push_error("[WorldItems] Cannot write inventory: %s" % output)
			get_tree().quit(1)
			return
		stream.store_string(JSON.stringify(report, "\t") + "\n")
	print("WORLD_ITEMS levels=%d keys=%d missing=%d" % [report["levels"].size(), report["total_by_key"].size(), report["missing"].size()])
	get_tree().quit(0 if report["missing"].is_empty() else 1)
