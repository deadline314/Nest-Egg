class_name RunOverwritePrompt
extends Control
## 使用遊戲共用實心面板；取消先取得焦點，返回會恢復原出發按鈕。

signal confirmed
signal canceled
const COPY := {
	"title": ["開始新遊戲", "新しいゲームを開始", "Replace current save?"],
	"warning": [
		"新遊戲會覆寫此存檔槽的進度。取消可保留原存檔。",
		"新しく始めると、このスロットの進行状況を上書きします。キャンセルすると現在のセーブを保持します。",
		"Starting a new game replaces the progress in this slot. Cancel to keep your save.",
	],
	"keep": ["保留原進度", "現在のセーブを保持", "Keep save"],
	"keep_hint": ["返回難度選擇，保留原存檔。", "セーブを保持して難易度選択に戻ります。", "Return to difficulty selection and keep your save."],
	"replace": ["覆寫並出發", "上書きして開始", "Replace and start"],
	"replace_hint": ["覆寫此存檔槽並開始新遊戲。", "このスロットを上書きして新しく始めます。", "Replace this slot and start a new game."],
}


var cancel_button: Button


func _ready() -> void:
	UiKit.fill_parent(self)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.96)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-205, -82)
	panel.size = Vector2(410, 164)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	panel.add_child(content)
	content.add_child(UiKit.with_role_font(UiKit.label(_text("title"), UiKit.FS_TITLE, Palette.CYAN), &"title"))
	var message := UiKit.label(_text("warning"), UiKit.FS_BODY)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	content.add_child(row)
	cancel_button = UiKit.button(_text("keep"), _cancel, _text("keep_hint"))
	cancel_button.custom_minimum_size = Vector2(170, 32)
	row.add_child(cancel_button)
	var overwrite := UiKit.button(_text("replace"), _confirm, _text("replace_hint"))
	overwrite.custom_minimum_size = Vector2(170, 32)
	row.add_child(overwrite)
	cancel_button.grab_focus.call_deferred()


static func _text(key: String) -> String:
	var language := maxi(0, StoryLocale.LANGUAGES.find(Story.language))
	return COPY[key][language]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


func _cancel() -> void:
	canceled.emit()
	queue_free()


func _confirm() -> void:
	confirmed.emit()
	queue_free()
