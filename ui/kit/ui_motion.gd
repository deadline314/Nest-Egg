class_name UiMotion
extends RefCounted
## 介面動態的共用小工具：依序滑入、數字跳動、閃紅。
## 節點在容器裡時先等一個影格讓版面排好，再以排好的位置為基準滑入。

const STEP := 0.06
const DISTANCE := 20.0
## 分頁切換的滑入時間與距離（像素）。
const SLIDE_TIME := 0.14
const SLIDE_DISTANCE := 14.0
const HOME_META := &"ui_motion_home"
const TWEEN_META := &"ui_motion_tween"


## 依序從左側滑入並淡入。開啟減少介面動態時直接顯示。
## 容器內的節點要等容器排好版才知道正確位置（版面是在影格結束時才排），所以先等兩個影格；
## 重複呼叫時會先停掉上一次的動畫並回到原位，不會以滑到一半的位置當基準。
static func stagger_in(nodes: Array, step := STEP, distance := DISTANCE, start_delay := 0.0) -> void:
	if nodes.is_empty():
		return
	var first: Control = nodes[0]
	if not is_instance_valid(first) or not first.is_inside_tree():
		return
	var tree := first.get_tree()
	if Settings.get_reduce_ui_motion():
		for item: Variant in nodes:
			if is_instance_valid(item) and item is Control:
				_stop_motion(item as Control)
				(item as Control).modulate.a = 1.0
		return
	for n: Variant in nodes:
		if is_instance_valid(n):
			_stop_motion(n as Control)
			(n as Control).modulate.a = 0.0
			var parent := (n as Control).get_parent()
			if parent is Container:
				(parent as Container).queue_sort()
	await tree.process_frame
	await tree.process_frame
	var index := 0
	for item: Variant in nodes:
		# 等待期間節點可能已被釋放（畫面切走），逐一檢查。
		if not is_instance_valid(item) or not (item as Control).is_inside_tree():
			continue
		var n := item as Control
		if Settings.get_reduce_ui_motion():
			n.modulate.a = 1.0
			continue
		var home := n.position
		n.set_meta(HOME_META, home)
		n.position = home + Vector2(-distance, 0)
		var tween := n.create_tween().set_parallel(true)
		n.set_meta(TWEEN_META, tween)
		var delay := start_delay + float(index) * step
		tween.tween_property(n, "position", home, 0.2).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(n, "modulate:a", 1.0, 0.16).set_delay(delay)
		index += 1


## 分頁或子頁切換（NE-389）：新內容從 offset 短距離滑回原位並淡入；offset 的方向就是內容進來的方向。
## 開啟減少介面動態時直接到位。動畫期間輸入照常；連續呼叫以最後一次為準，不排隊。
## 結束後請容器重新排版一次，所以即使中途版面改變，最後的位置一定是對的。
static func slide_in(node: Control, offset: Vector2, seconds := SLIDE_TIME) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_stop_motion(node)
	node.modulate.a = 1.0
	if Settings.get_reduce_ui_motion() or not offset.is_finite() or seconds <= 0.0:
		return
	var home := node.position
	node.set_meta(HOME_META, home)
	node.position = home + offset
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel(true)
	node.set_meta(TWEEN_META, tween)
	tween.tween_property(node, "position", home, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, seconds * 0.8)
	tween.chain().tween_callback(_settle.bind(node))


static func _settle(node: Control) -> void:
	if not is_instance_valid(node):
		return
	node.remove_meta(TWEEN_META)
	var parent := node.get_parent()
	if parent is Container:
		(parent as Container).queue_sort()


## 停掉節點上進行中的滑入並回到原位。
static func _stop_motion(n: Control) -> void:
	if not n.has_meta(TWEEN_META):
		return
	var tween: Variant = n.get_meta(TWEEN_META)
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
		n.position = n.get_meta(HOME_META)
	n.remove_meta(TWEEN_META)


## 逐項顯示（結算畫面用）：每隔 interval 秒顯示下一項；should_stop 回傳 true 時立刻顯示剩下全部。
static func reveal_sequence(nodes: Array, interval: float, on_each: Callable = Callable(),
		should_stop: Callable = Callable()) -> void:
	for item: Variant in nodes:
		if is_instance_valid(item):
			(item as Control).modulate.a = 0.0
	for item: Variant in nodes:
		if not is_instance_valid(item) or not (item as Control).is_inside_tree():
			return
		var n := item as Control
		n.modulate.a = 1.0
		if on_each.is_valid():
			on_each.call(n)
		if Settings.get_reduce_ui_motion():
			continue
		if should_stop.is_valid() and should_stop.call():
			for rest: Variant in nodes:
				if is_instance_valid(rest):
					(rest as Control).modulate.a = 1.0
			return
		await n.get_tree().create_timer(interval, true, false, true).timeout


## 數字從 from 數到 to。
static func count_up(label: Label, from: int, to: int, seconds: float, format := "%d") -> void:
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	if Settings.get_reduce_ui_motion():
		label.text = format % to
		return
	var tween := label.create_tween()
	tween.tween_method(func(v: float) -> void:
		if is_instance_valid(label):
			label.text = format % roundi(v), float(from), float(to), seconds)
