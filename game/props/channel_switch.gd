class_name ChannelSwitch
extends MechanismSwitch
## 頻道開關：切換時通知同頻道的閘門與升降梯（EventBus.mechanism_toggled）。


func _apply(is_active: bool, silent: bool) -> void:
	if silent:
		return
	EventBus.mechanism_toggled.emit(data.channel, is_active)
	EventBus.toast_requested.emit("%s：%s" % [data.display_name, "啟動" if is_active else "關閉"])
