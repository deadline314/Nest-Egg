class_name TextTraffic
extends RefCounted
## 文字的交通管制（NE-491）：畫面上一次只有一個「在講話」的文字塊。
## 互動提示（按鍵邀請）不是講話，永遠可以顯示；過場對話與通訊本來就會暫停或蓋住其他文字。
## 其餘想講話的來源（對主角說的話、路人閒聊、教學看板）每一格提出要求，只有優先順序最高的拿到發言；
## 同樣高時先來的保留發言，不會兩邊搶著閃動。沒拿到的延後（氣泡等著、看板只亮著螢幕不展開文字）。
## 加上互動提示，同一格畫面上展開的文字塊最多兩塊；位置不重疊由 PromptLayout 負責。

## 講話的優先順序：數字大的先講。
enum Voice { NONE = 0, BOARD = 1, AMBIENT = 2, ADDRESSED = 3 }
## 一個來源連續幾格沒有提出要求就視為不講了（容許一格的處理順序差）。
const STALE_FRAMES := 2

## 來源的 instance id -> [優先順序, 最後一次要求的影格, 第一次要求的影格]
static var _claims: Dictionary[int, PackedInt64Array] = {}


## 這一格想講話；回傳現在是不是輪到它。每一格想講就要呼叫一次。
static func claim(owner: Object, voice: int) -> bool:
	if owner == null or voice <= Voice.NONE:
		return true
	var id := owner.get_instance_id()
	var frame := Engine.get_process_frames()
	var since := _claims[id][2] if _claims.has(id) else frame
	_claims[id] = PackedInt64Array([voice, frame, since])
	return speaker() == id


## 不講了（離開範圍、講完、節點離開場景樹）。
static func release(owner: Object) -> void:
	if owner != null:
		_claims.erase(owner.get_instance_id())


## 目前拿到發言的來源（instance id）；沒有人要講時是 0。
static func speaker() -> int:
	var frame := Engine.get_process_frames()
	var best := 0
	var best_voice := -1
	var best_since := 0
	for id: int in _claims.keys():
		var claim_data: PackedInt64Array = _claims[id]
		if frame - claim_data[1] > STALE_FRAMES or not is_instance_id_valid(id):
			_claims.erase(id)
			continue
		var voice := int(claim_data[0])
		if voice > best_voice or (voice == best_voice and claim_data[2] < best_since):
			best = id
			best_voice = voice
			best_since = claim_data[2]
	return best


## 測試用：清掉所有要求。
static func reset() -> void:
	_claims.clear()
