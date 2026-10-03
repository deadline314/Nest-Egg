class_name PlacementChecks
extends RefCounted
## 關卡裡敵人配置的共用檢查（第二批敵人的測試共用）。

## 第一次遭遇的安全空間：這格的敵人左邊 safe_tiles 格內沒有其他種類的敵人（同種成群不算）。
static func first_encounter_clear(layout: LevelLayout, cell: Vector2i, safe_tiles := 5.0) -> bool:
	var own_id := &""
	for spawn: Dictionary in layout.spawns:
		var enemy := spawn["resource"] as EnemyData
		if enemy != null and spawn["cell"] == cell:
			own_id = enemy.id
	for spawn: Dictionary in layout.spawns:
		var other := spawn["resource"] as EnemyData
		var other_cell: Vector2i = spawn["cell"]
		if other == null or other_cell == cell or other.id == own_id:
			continue
		if other_cell.x < cell.x and cell.x - other_cell.x < safe_tiles:
			return false
	return true


## 這個關卡裡某種敵人的所有配置格。
static func cells_of(layout: LevelLayout, enemy_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for spawn: Dictionary in layout.spawns:
		var enemy := spawn["resource"] as EnemyData
		if enemy != null and enemy.id == enemy_id:
			cells.append(spawn["cell"])
	return cells
