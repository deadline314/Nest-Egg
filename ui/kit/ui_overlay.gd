class_name UiOverlay
extends RefCounted
## 全螢幕覆蓋畫面（設定、圖鑑…）的共用開法：開啟期間底下的畫面一律隱藏，所以不會疊在一起、
## 也不會被聚焦或操作；關閉後還原，焦點回到原本的控制項。


## 把 overlay 加進 host 之上。host 底下原本顯示中的畫面暫時隱藏，overlay 離開場景樹時還原。
static func open(host: Control, overlay: Control) -> void:
	# 先記焦點再隱藏：控制項一隱藏就會失去焦點。
	var previous_focus := host.get_viewport().gui_get_focus_owner() if host.is_inside_tree() else null
	var covered: Array[Control] = []
	for child in host.get_children():
		if child is Control and (child as Control).visible:
			covered.append(child)
			(child as Control).visible = false
	host.add_child(overlay)
	overlay.tree_exited.connect(_restore.bind(covered, previous_focus), CONNECT_ONE_SHOT)


static func _restore(covered: Array[Control], previous_focus: Control) -> void:
	for control in covered:
		if is_instance_valid(control):
			control.visible = true
	if is_instance_valid(previous_focus) and previous_focus.is_inside_tree():
		previous_focus.grab_focus.call_deferred()
