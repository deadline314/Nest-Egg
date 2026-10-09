class_name EyeBlink
extends RefCounted
## Deterministic, data-driven blink timing shared by Rin and NPC rigs.

const OPEN: StringName = &"open"
const HALF: StringName = &"half"
const CLOSED: StringName = &"closed"

const DEFAULT_MEDIAN_INTERVAL := 3.5
const DEFAULT_LOG_SIGMA := 0.35
const DEFAULT_DURATION_RANGE := Vector2(0.12, 0.15)
const DEFAULT_TALKING_FREQUENCY := 2.0
const MIN_INTERVAL := 0.5
const MAX_INTERVAL := 60.0
const MAX_LOG_SIGMA := 0.8
const MAX_TALKING_FREQUENCY := 4.0
const MAX_DELTA := 0.1
const TIME_EPSILON := 0.000001

var _rng := RandomNumberGenerator.new()
var _skin := ""
var _seed := 0
var _median_interval := DEFAULT_MEDIAN_INTERVAL
var _log_sigma := DEFAULT_LOG_SIGMA
var _duration_min := DEFAULT_DURATION_RANGE.x
var _duration_max := DEFAULT_DURATION_RANGE.y
var _talking_frequency := DEFAULT_TALKING_FREQUENCY
var _time_to_next := 0.0
var _blink_duration := 0.0
var _blink_elapsed := 0.0
var _blinking := false
var _state: StringName = OPEN


## Config keys: median_interval, log_sigma, duration_range [min, max], talking_frequency, seed.
## Duration overrides stay within the ticket's 120–150 ms acceptance window.
func setup(skin: String, config: Dictionary = {}) -> void:
	_skin = skin.strip_edges() if not skin.strip_edges().is_empty() else "unknown"
	_median_interval = _number(config, "median_interval", DEFAULT_MEDIAN_INTERVAL, MIN_INTERVAL, MAX_INTERVAL)
	_log_sigma = _number(config, "log_sigma", DEFAULT_LOG_SIGMA, 0.0, MAX_LOG_SIGMA)
	_talking_frequency = _number(config, "talking_frequency", DEFAULT_TALKING_FREQUENCY, 1.0, MAX_TALKING_FREQUENCY)
	_duration_min = DEFAULT_DURATION_RANGE.x
	_duration_max = DEFAULT_DURATION_RANGE.y
	var duration_value: Variant = config.get("duration_range", [DEFAULT_DURATION_RANGE.x, DEFAULT_DURATION_RANGE.y])
	if typeof(duration_value) == TYPE_ARRAY and (duration_value as Array).size() == 2 \
			and _is_number(duration_value[0]) and _is_number(duration_value[1]):
		var low := float(duration_value[0])
		var high := float(duration_value[1])
		if is_finite(low) and is_finite(high) and low >= DEFAULT_DURATION_RANGE.x and high <= DEFAULT_DURATION_RANGE.y and low <= high:
			_duration_min = low
			_duration_max = high
		else:
			_warn_invalid("duration_range", "expected finite ordered seconds within 0.12–0.15")
	else:
		_warn_invalid("duration_range", "expected two numeric seconds within 0.12–0.15")
	var seed_value: Variant = config.get("seed", 0)
	if typeof(seed_value) == TYPE_INT:
		_seed = int(seed_value)
	else:
		_seed = 0
		_warn_invalid("seed", "expected an integer")
	reset()


## Advances the timer without allocating containers. Large frame spikes open the eye and pause timing.
func update(delta: float, talking: bool, disabled: bool = false) -> StringName:
	if disabled:
		_blinking = false
		_blink_elapsed = 0.0
		_state = OPEN
		return _state
	if not is_finite(delta) or delta <= 0.0:
		return _state
	if delta > MAX_DELTA:
		_blinking = false
		_blink_elapsed = 0.0
		_state = OPEN
		return _state
	if _blinking:
		_blink_elapsed += delta
		if _blink_elapsed + TIME_EPSILON >= _blink_duration:
			_blinking = false
			_state = OPEN
		else:
			var progress := _blink_elapsed / _blink_duration
			_state = HALF if progress < 0.25 or progress >= 0.75 else CLOSED
		return _state
	_time_to_next -= delta * (_talking_frequency if talking else 1.0)
	if _time_to_next <= 0.0:
		_blinking = true
		_blink_elapsed = 0.0
		_blink_duration = _rng.randf_range(_duration_min, _duration_max)
		_time_to_next = _sample_interval()
		_state = HALF
	return _state


## Restarts the seeded sequence, so reset() reproduces the same timing.
func reset() -> void:
	_rng.seed = hash("eye-blink:%s:%d" % [_skin, _seed])
	_blinking = false
	_blink_elapsed = 0.0
	_blink_duration = 0.0
	_state = OPEN
	_time_to_next = _sample_interval()


func _sample_interval() -> float:
	var log_interval := log(_median_interval) + _rng.randfn(0.0, _log_sigma)
	return clampf(exp(log_interval), MIN_INTERVAL, MAX_INTERVAL)


func _number(config: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	if not config.has(key):
		return fallback
	var value: Variant = config[key]
	if _is_number(value):
		var number := float(value)
		if is_finite(number) and number >= low and number <= high:
			return number
	_warn_invalid(key, "expected a finite number in [%s, %s]" % [low, high])
	return fallback


func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


func _warn_invalid(field: String, expected: String) -> void:
	push_warning("[EyeBlink] %s.config.%s invalid; using safe default (%s)" % [_skin, field, expected])
