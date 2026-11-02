extends RefCounted
## Explicit second-chapter boundaries; other story payloads cannot enable them.
const SOURCE := "res://data/story/ch2_heron.json"
const NPC_SOURCES := {
	"ch2_t_s05_gate": {
		"npc": "res://data/npcs/ch2_patroller.tres",
		"levels": ["res://data/levels/ch2_market_gate.tres"],
	},
}
const BOUNDARIES := {
	"ch2_t_s05_gate": {
		"policy": "main_terminal_results_v1", "then": "", "mode": "dialogue",
		"when": {"all": [{"flag": "ch2_brief_done", "equals": true}, {"not": {"flag": "ch2_gate_checked", "equals": true}}]},
		"operations": [{"kind": "flag", "id": "ch2_gate_checked", "value": true}],
	},
}
