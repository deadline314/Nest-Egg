class_name ChannelSwitch
extends MechanismSwitch
## 頻道開關：切換時通知同頻道的閘門與升降梯（EventBus.mechanism_toggled）。


const ACTIVATED: Dictionary[String, String] = {
	"en": "%s activated.",
	"ja": "%s：起動",
}
const DEACTIVATED: Dictionary[String, String] = {
	"en": "%s deactivated.",
	"ja": "%s：停止",
}


func _apply(is_active: bool, silent: bool) -> void:
	if silent:
		return
	EventBus.mechanism_toggled.emit(data.channel, is_active)
	var status := StoryLocale.optional_text(ACTIVATED, Story.language, "%s：啟動") if is_active \
		else StoryLocale.optional_text(DEACTIVATED, Story.language, "%s：關閉")
	EventBus.toast_requested.emit(status % data.display_name_for(Story.language))
