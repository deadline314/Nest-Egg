class_name JanusConfig
extends RefCounted
## JANUS 的純資料設定快取。與 Enemy 繼承鏈分開，避免跨章載入 behavior
## 時由衍生腳本的 static 欄位保留整個型別圖；不保留節點或指向頭目的 callable。

const CONFIG_KEY := "gatekeeper"

## 從 janus.json 的 gatekeeper 段讀的設定（缺欄位時用這裡的預設）。
const DEFAULTS := {
	"wake_flag": "ch3_janus_intro_seen", "disabled_flag": "ch3_janus_disabled",
	"misses_flag": "ch3_janus_shield_misses", "comm_flag": "ch3_janus_comm_broken",
	"stability_flag": "ch3_janus_device_stability", "lost_flag": "ch3_janus_lost_once",
	"bark_sorry": "ch3_c11_bark_sorry", "bark_repeat": "ch3_c11_bark_repeat", "defeat_hint": "ch3_c11_defeat_hint",
	"turn_delay": 0.8, "replay_chance": 0.3, "replay_max": 2, "seed": 271,
	"crack_misses": 3, "comm_hits": 6, "pin_offset": [-12.0, -22.0],
}

static var _config_cache: Dictionary = {}

static func load_for(id: StringName) -> Dictionary:
	var key := String(id)
	if _config_cache.has(key):
		return _config_cache[key]
	var merged := DEFAULTS.duplicate(true)
	var path := BossPattern.DIR % key
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var section: Variant = (parsed as Dictionary).get(CONFIG_KEY, {}) if parsed is Dictionary else {}
	if section is Dictionary:
		for field: String in section:
			if merged.has(field) and typeof(section[field]) in [typeof(merged[field]), TYPE_FLOAT, TYPE_INT]:
				merged[field] = section[field]
			else:
				push_error("[JanusBoss] %s 的 %s.%s 不認得或型別不對，改用預設" % [path, CONFIG_KEY, field])
	else:
		push_error("[JanusBoss] %s 的 %s 不是物件，全部用預設" % [path, CONFIG_KEY])
	_config_cache[key] = merged
	return merged



static func clear_cache() -> void:
	_config_cache.clear()
