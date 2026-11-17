extends Node
class Probe extends "res://tools/enemy_glow_probe.gd":
	func _ready() -> void:
		pass

var _checks := 0
var _failures := 0
func _check(value: bool, name: String) -> void:
	_checks += 1
	_failures += int(not value)
	print("ENEMY_GLOW_CPU:", "PASS" if value else "FAIL", ":", name)
func _record(count := 6, ratio := 1.04, pair_count := 60) -> Dictionary:
	var pairs: Array = []
	for index in pair_count:
		pairs.append({"round": index, "on_first": index % 2 == 0, "on_ms": ratio, "off_ms": 1.0})
	return {"glowing_enemies": count, "active_lights": 8, "max_lights": 8, "pairs": pairs}
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var probe := Probe.new()
	_check(probe.has_method("_accept_perf"), "performance result has an enforceable acceptance gate")
	_check(probe.has_method("_initial_light_valid"), "death evidence requires an initially valid lit source")
	if probe.has_method("_accept_perf"):
		for entry: Array in [["valid six", _record(), true], ["exact105%", _record(6, 1.05), true],
			["unrounded overspeed", _record(6, 1.050001), false], ["zero lights", _record(0), false],
			["five lights", _record(5), false], ["missing pairs", _record(6, 1.0, 0), false]]:
			probe._failures = 0
			var result: bool = probe._accept_perf(entry[1])
			_check(result == entry[2] and probe._failures == (0 if entry[2] else 1), entry[0] + " reaches actual failure counter")
		var invalid := _record()
		invalid["pairs"][0]["off_ms"] = 0.0
		probe._failures = 0
		_check(not probe._accept_perf(invalid) and probe._failures == 1, "zero baseline pair is rejected")
		invalid = _record()
		invalid["pairs"][0]["on_ms"] = NAN
		probe._failures = 0
		_check(not probe._accept_perf(invalid) and probe._failures == 1, "non-finite timing is rejected")
		invalid = _record()
		invalid["active_lights"] = 9
		probe._failures = 0
		_check(not probe._accept_perf(invalid) and probe._failures == 1, "quality budget overflow is rejected")
	if probe.has_method("_initial_light_valid"):
		_check(not probe._initial_light_valid(null), "missing death light is rejected")
		var light := PointLight2D.new()
		light.texture = GradientTexture2D.new()
		add_child(light)
		_check(probe._initial_light_valid(light), "initially lit real light node is accepted")
		light.enabled = false
		_check(not probe._initial_light_valid(light), "initially disabled light cannot prove a fade")
		light.enabled = true
		light.energy = 0.0
		_check(not probe._initial_light_valid(light), "initially dark light cannot prove a fade")
		light.free()
	probe.free()
	print("ENEMY_GLOW_CPU_RESULT:", _checks, "/", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
