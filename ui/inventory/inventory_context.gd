class_name InventoryContext
extends RefCounted
## 背包各分頁共用的上下文：玩家，以及向畫面底部說明列送出訊息的管道。

## 操作結果訊息（例如「回復 2 格生命」）；背包畫面顯示在底部說明列。
signal message(text: String, is_warning: bool)

var player: Player


func _init(p_player: Player) -> void:
	player = p_player


func is_valid() -> bool:
	return is_instance_valid(player) and not player.is_dead()


func say(text: String, is_warning := false) -> void:
	message.emit(text, is_warning)
