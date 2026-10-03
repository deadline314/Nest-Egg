class_name InputFeelSuite
extends TestSuite
## 輸入手感（NE-145）：緩衝與取消窗口來自資料、壞值退回預設；手把瞄準輔助只給手把、有錐形與距離限制、玩家輸入優先；
## 輸入延遲量測；衝刺提前按會排隊。

func run() -> void:
	_test_windows_from_data()
	_test_aim_assist()
	_test_latency()
	await _test_dash_buffer()


func _test_windows_from_data() -> void:
	var errors: PackedStringArray = InputFeel.validate()
	check(errors.is_empty(), "input feel data has no errors: %s" % ", ".join(errors))
	for key in InputFeel.KNOWN_BUFFERS:
		check(InputFeel.window(key, -1.0) >= 0.0, "window %s is defined in data" % key)
	check(is_equal_approx(MeleeData.buffer_time(), InputFeel.window("melee_buffer", 0.0)), "the melee buffer comes from the input data")
	check(InputFeel.window("test_no_such_window", 0.07) == 0.07, "a missing window falls back to the given default")


func _targets(positions: Array) -> Array:
	var nodes: Array = []
	for pos: Vector2 in positions:
		var node := Node2D.new()
		runner.get_tree().root.add_child(node)
		node.global_position = pos
		nodes.append(node)
	return nodes


func _free(nodes: Array) -> void:
	for node: Node in nodes:
		node.queue_free()


func _test_aim_assist() -> void:
	var origin := Vector2(0.0, 0.0)
	# 目標在搖桿方向微偏處（敵人瞄點是腳底往上 20）：往目標拉一點。
	var near := _targets([Vector2(200.0, 20.0 + 14.0)])
	var pulled := InputFeel.assist(origin, Vector2.RIGHT, near, 0.0, true)
	var target_angle := Vector2(200.0, 14.0).angle()
	check(pulled.angle() > 0.0 and pulled.angle() < target_angle + 0.001, "the assist pulls the aim toward a target inside the cone (%.3f of %.3f rad)" % [pulled.angle(), target_angle])
	# 只給手把。
	check(InputFeel.assist(origin, Vector2.RIGHT, near, 0.0, false) == Vector2.RIGHT, "the mouse is never assisted")
	# 錐形與距離之外不拉。
	var outside := _targets([Vector2(200.0, 20.0 + 120.0), Vector2(900.0, 20.0)])
	check(InputFeel.assist(origin, Vector2.RIGHT, outside, 0.0, true) == Vector2.RIGHT, "targets outside the cone or too far away do not pull")
	# 玩家輸入優先：搖桿快速轉動時輔助關閉。
	check(InputFeel.assist(origin, Vector2.RIGHT, near, 99.0, true) == Vector2.RIGHT, "fast stick turns switch the assist off")
	# 拉力有上限：最多只拉到目標，而且遠小於整個錐形。
	var assisted_angle := absf(pulled.angle())
	check(assisted_angle <= absf(target_angle) and assisted_angle >= 0.0, "the assist never overshoots the target")
	check(InputFeel.assist(origin, Vector2.ZERO, near, 0.0, true) == Vector2.ZERO, "no stick input means no assist")
	_free(near)
	_free(outside)


func _test_latency() -> void:
	InputFeel.reset_latency()
	check(InputFeel.resolve(&"shoot") == -1.0, "resolving an action that was never pressed gives nothing")
	InputFeel.mark(&"shoot")
	OS.delay_msec(5)
	var elapsed := InputFeel.resolve(&"shoot")
	check(elapsed >= 4.0 and elapsed < 500.0 and is_equal_approx(InputFeel.last_ms, elapsed), "the latency is the time from the press to the effect (%.1f ms)" % elapsed)
	check(InputFeel.samples == 1 and is_equal_approx(InputFeel.average_ms, elapsed), "the running average follows the samples")
	check(Feel.read_counters().has("input_latency_ms"), "the diagnostics expose the input latency")
	InputFeel.reset_latency()


func _test_dash_buffer() -> void:
	var level := await start_level(PropsSuite.level_data())
	var player := level.player
	await physics_frames(10)
	player._dash_cooldown_left = 0.08
	player._try_dash(1.0)
	check(player.state != Player.State.DASH and player._dash_buffer_left > 0.0, "a dash pressed during the cooldown is queued")
	await physics_frames(12)
	check(player._dash_buffer_left == 0.0 and (player.state == Player.State.DASH or player._dash_cooldown_left > 0.0), "the queued dash fires when the cooldown ends")
	await physics_frames(3)
	await end_level(level)
