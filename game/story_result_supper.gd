extends RefCounted
## Exact authored stall family. Pure metadata; shared validation lives in Sources.
const NPC_SOURCE := {
	"npc": "res://data/npcs/ch1_ali_stall.tres",
	"levels": [
		"res://data/levels/ch1_stall.tres"
	]
}
const BOUNDARIES := {
	"ch1_t_supper_pay": {
		"policy": "main_source_results_continuation_v1",
		"then": "ch1_t_supper_paid_goodbye",
		"operations": [
			{
				"kind": "transaction",
				"id": "ch1.revival_meal.paid"
			},
			{
				"kind": "flag",
				"id": "ch1_supper_done",
				"value": true
			}
		],
		"failures": {
			"insufficient_credits": "ch1_t_supper_insufficient"
		}
	},
	"ch1_t_supper_paid_goodbye": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"operations": [],
		"pending_after": "ch1_t_supper_pay"
	},
	"ch1_t_supper_tab": {
		"policy": "main_source_results_continuation_v1",
		"then": "ch1_t_supper_tab_goodbye",
		"operations": [
			{
				"kind": "transaction",
				"id": "ch1.revival_meal.tab"
			},
			{
				"kind": "item_acquire",
				"id": "ch1_lounge_tab"
			},
			{
				"kind": "flag",
				"id": "ch1_supper_done",
				"value": true
			}
		]
	},
	"ch1_t_supper_tab_goodbye": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"operations": [],
		"pending_after": "ch1_t_supper_tab"
	},
	"ch1_t_supper_leave_none": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"operations": [
			{
				"kind": "flag",
				"id": "ch1_supper_done",
				"value": true
			}
		]
	},
	"ch1_t_supper_return": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"operations": [
			{
				"kind": "flag",
				"id": "ch1_supper_choice",
				"value": "unset"
			}
		],
		"repeatable": true,
		"repeat_condition": {
			"flag": "ch1_supper_can_rechoose",
			"equals": true
		}
	},
	"ch1_t_supper_stay_host": {
		"policy": "main_source_results_continuation_v1",
		"then": "ch1_t_supper_stay_meal",
		"operations": [
			{
				"kind": "transaction",
				"id": "ch1.revival_meal.gift"
			},
			{
				"kind": "flag",
				"id": "ch1_supper_host_accepted",
				"value": true
			}
		]
	},
	"ch1_t_supper_stay_host_none": {
		"policy": "main_flags_continuation_v1",
		"then": "ch1_t_supper_stay_meal",
		"operations": [
			{
				"kind": "flag",
				"id": "ch1_supper_host_accepted",
				"value": true
			}
		]
	},
	"ch1_t_supper_stay_meal": {
		"policy": "main_flags_continuation_v1",
		"then": "ch1_t_supper_stay_address",
		"operations": [
			{
				"kind": "flag",
				"id": "ch1_supper_meal_done",
				"value": true
			}
		]
	},
	"ch1_t_supper_stay_address": {
		"policy": "main_terminal_results_v1",
		"then": "",
		"operations": [
			{
				"kind": "flag",
				"id": "knows_ali_address",
				"value": true
			},
			{
				"kind": "flag",
				"id": "sq1_first_supper_done",
				"value": true
			},
			{
				"kind": "flag",
				"id": "ch1_supper_done",
				"value": true
			}
		]
	}
}
const CHOICES := {
	"ch1_t_supper_choice_ordered": {
		"default": "return",
		"options": [
			{
				"id": "leave",
				"target": "ch1_t_supper_leave_options",
				"flags": {
					"ch1_supper_choice": "leave"
				}
			},
			{
				"id": "stay",
				"target": "ch1_t_supper_host_prompt",
				"flags": {
					"ch1_supper_choice": "stay"
				}
			},
			{
				"id": "return",
				"target": "",
				"flags": {}
			}
		],
		"waits": {
			"6": 0.35
		}
	},
	"ch1_t_supper_choice_none": {
		"default": "return",
		"options": [
			{
				"id": "leave",
				"target": "ch1_t_supper_leave_none",
				"flags": {
					"ch1_supper_choice": "leave"
				}
			},
			{
				"id": "stay",
				"target": "ch1_t_supper_host_none_prompt",
				"flags": {
					"ch1_supper_choice": "stay"
				}
			},
			{
				"id": "return",
				"target": "",
				"flags": {}
			}
		]
	},
	"ch1_t_supper_leave_options": {
		"default": "rechoose",
		"options": [
			{
				"id": "pay",
				"target": "ch1_t_supper_pay",
				"flags": {}
			},
			{
				"id": "defer",
				"target": "ch1_t_supper_tab_confirm",
				"flags": {}
			},
			{
				"id": "rechoose",
				"target": "ch1_t_supper_return",
				"flags": {},
				"when": {
					"flag": "ch1_supper_can_rechoose",
					"equals": true
				}
			}
		]
	},
	"ch1_t_supper_insufficient": {
		"default": "return",
		"options": [
			{
				"id": "defer",
				"target": "ch1_t_supper_tab_confirm",
				"flags": {}
			},
			{
				"id": "stay",
				"target": "ch1_t_supper_return",
				"flags": {}
			},
			{
				"id": "return",
				"target": "",
				"flags": {}
			}
		]
	},
	"ch1_t_supper_tab_confirm": {
		"default": "return",
		"options": [
			{
				"id": "confirm",
				"target": "ch1_t_supper_tab",
				"flags": {}
			},
			{
				"id": "return",
				"target": "",
				"flags": {}
			}
		]
	},
	"ch1_t_supper_host_prompt": {
		"default": "return",
		"options": [
			{
				"id": "accept",
				"target": "ch1_t_supper_stay_host",
				"flags": {}
			},
			{
				"id": "return",
				"target": "ch1_t_supper_return",
				"flags": {},
				"when": {
					"flag": "ch1_supper_can_rechoose",
					"equals": true
				}
			}
		]
	},
	"ch1_t_supper_host_none_prompt": {
		"default": "return",
		"options": [
			{
				"id": "accept",
				"target": "ch1_t_supper_stay_host_none",
				"flags": {}
			},
			{
				"id": "return",
				"target": "ch1_t_supper_return",
				"flags": {},
				"when": {
					"flag": "ch1_supper_can_rechoose",
					"equals": true
				}
			}
		]
	}
}
