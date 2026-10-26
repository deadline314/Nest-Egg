extends "res://tests/helpers/ali_completion_base.gd"
## Reuse the same real source, menu, refusal and waiter contract; change only
## the exact boundary selected when its original authored segment starts.
func _inject(id: StringName, kind: StringName) -> void:
	var reception := &"ch1_t_ali_order" if ordered else &"ch1_t_ali_sit"
	if id != reception:
		return
	target = reception
	super._inject(id, kind)
