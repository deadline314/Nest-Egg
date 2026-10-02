class_name WorldState
extends RefCounted
## 世界狀態快照：關卡中會改變的東西（被打破的箱子、開關、閘門、電力…）在檢查點時存下，
## 重生時（關卡會整個重建）還原。加入群組 GROUP 並實作下列三個方法即可參與：
##   state_key() -> String        同一關內固定且唯一（建議用種類＋格座標）
##   capture_state() -> Variant   可複製的簡單資料（bool、數字、字串、Dictionary）
##   restore_state(state: Variant) -> void   直接套用，不播放效果、不發訊號
## 快照裡找不到的 key 保持初始狀態；快照裡多出來的 key（資料改版後）直接忽略，不會報錯。

const GROUP := &"stateful"


static func capture(tree: SceneTree) -> Dictionary:
	var snapshot: Dictionary = {}
	for node in tree.get_nodes_in_group(GROUP):
		if not node.has_method(&"state_key") or not node.has_method(&"capture_state"):
			continue
		var key: String = node.call(&"state_key")
		if snapshot.has(key):
			push_warning("[WorldState] 狀態 key 重複：%s" % key)
			continue
		snapshot[key] = node.call(&"capture_state")
	return snapshot


static func restore(tree: SceneTree, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	for node in tree.get_nodes_in_group(GROUP):
		if not node.has_method(&"state_key") or not node.has_method(&"restore_state"):
			continue
		var key: String = node.call(&"state_key")
		if snapshot.has(key):
			node.call(&"restore_state", snapshot[key])
