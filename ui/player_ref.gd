class_name PlayerRef
extends RefCounted
## UI 取得玩家的共用方式：以弱參照快取，玩家被移除或重生時自動重新尋找，不會持有失效物件。

var _ref: WeakRef


func get_player(tree: SceneTree) -> Player:
	var player: Player = _ref.get_ref() as Player if _ref != null else null
	if player == null and tree != null:
		player = tree.get_first_node_in_group(&"player") as Player
		_ref = weakref(player) if player != null else null
	return player
