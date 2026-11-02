extends RefCounted
## Explicit second-chapter boundaries; other story payloads cannot enable them.
const SOURCE := "res://data/story/ch2_heron.json"
const NPC_SOURCES := {
	"ch2_t_s05_gate": {
		"npc": "res://data/npcs/ch2_patroller.tres",
		"levels": [
			"res://data/levels/ch2_market_gate.tres"
		]
	},
	"ch2_t_s08_contract": {
		"npc": "res://data/npcs/ch2_rent_window.tres",
		"levels": [
			"res://data/levels/ch2_market.tres"
		]
	},
	"ch2_t_s08_collection": {
		"npc": "res://data/npcs/ch2_collection_book.tres",
		"levels": [
			"res://data/levels/ch2_loading.tres"
		]
	},
	"ch2_t_s08_banyan": {
		"npc": "res://data/npcs/ch2_banyan.tres",
		"levels": [
			"res://data/levels/ch2_market.tres"
		]
	},
	"ch2_t_s08_rumor": {
		"npc": "res://data/npcs/ch2_hawker.tres",
		"levels": [
			"res://data/levels/ch2_market.tres"
		]
	},
	"ch2_t_s09_guard": {
		"npc": "res://data/npcs/ch2_guard.tres",
		"levels": [
			"res://data/levels/ch2_loading.tres"
		]
	},
	"ch2_t_s09_lever": {
		"npc": "res://data/npcs/ch2_sc1_lever.tres",
		"levels": [
			"res://data/levels/ch2_loading.tres"
		]
	}
}
const BOUNDARIES := {
	"ch2_t_s05_gate": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "dialogue",
		"when": {
			"all": [
				{
					"flag": "ch2_brief_done",
					"equals": true
				},
				{
					"not": {
						"flag": "ch2_gate_checked",
						"equals": true
					}
				}
			]
		},
		"operations": [
			{
				"kind": "flag",
				"id": "ch2_gate_checked",
				"value": true
			}
		]
	},
	"ch2_t_s08_contract": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "dialogue",
		"when": {
			"not": {
				"flag": "ch2_evidence_contract",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "item_acquire",
				"id": "ch2_evidence_contract"
			},
			{
				"kind": "flag",
				"id": "ch2_evidence_contract",
				"value": true
			}
		]
	},
	"ch2_t_s08_collection": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "animated",
		"when": {
			"not": {
				"flag": "ch2_evidence_collection",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "item_acquire",
				"id": "ch2_evidence_collection"
			},
			{
				"kind": "flag",
				"id": "ch2_evidence_collection",
				"value": true
			}
		]
	},
	"ch2_t_s08_banyan": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "dialogue",
		"when": {
			"not": {
				"flag": "ch2_banyan_heard",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "flag",
				"id": "ch2_banyan_heard",
				"value": true
			}
		]
	},
	"ch2_t_s08_rumor": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "dialogue",
		"when": {
			"not": {
				"flag": "ch2_rumor_heard",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "flag",
				"id": "ch2_rumor_heard",
				"value": true
			}
		]
	},
	"ch2_t_s09_guard": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "dialogue",
		"when": {
			"not": {
				"flag": "ch2_guard_seen",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "flag",
				"id": "ch2_guard_seen",
				"value": true
			}
		]
	},
	"ch2_t_s09_lever": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"mode": "animated",
		"when": {
			"not": {
				"flag": "ch2_sc1_open",
				"equals": true
			}
		},
		"operations": [
			{
				"kind": "flag",
				"id": "ch2_sc1_open",
				"value": true
			}
		]
	}
}
