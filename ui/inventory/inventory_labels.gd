extends RefCounted
## Backpack and counter navigation labels in the selected game language.

const TEXT := {
	&"pack_title": ["背包", "所持品", "Inventory"],
	&"counter_title": ["補給點", "補給所", "Supply counter"],
	&"credits": ["信用點　¥%d", "クレジット ¥%d", "Credits ¥%d"],
	&"credits_help": ["商店、改裝、義體與典當使用的信用點", "購入、改造、義体、質入れに使うクレジット", "Credits for purchases, upgrades, cyberware and pawning"],
	&"bag_keys": ["{inventory} 關閉　%s　↑↓ 選擇　{ui_accept} 確認", "{inventory} 閉じる　%s　↑↓ 選択　{ui_accept} 決定", "{inventory} Close  %s  ↑↓ Select  {ui_accept} OK"],
	&"bag_pad": ["{ui_cancel} 返回　%s　{ui_accept} 確認", "{ui_cancel} 戻る　%s　{ui_accept} 決定", "{ui_cancel} Back  %s  {ui_accept} OK"],
	&"shop_keys": ["{ui_cancel} 離開%s　↑↓ 選擇　{ui_accept} 確認", "{ui_cancel} 閉じる%s　↑↓ 選択　{ui_accept} 決定", "{ui_cancel} Close%s  ↑↓ Select  {ui_accept} OK"],
	&"shop_pad": ["{ui_cancel} 返回%s　{ui_accept} 確認", "{ui_cancel} 戻る%s　{ui_accept} 決定", "{ui_cancel} Back%s  {ui_accept} OK"],
	&"tabs": ["{inventory_prev_tab}/{inventory_next_tab} 分頁", "{inventory_prev_tab}/{inventory_next_tab} 切替", "{inventory_prev_tab}/{inventory_next_tab} Tabs"],
	&"weapons": ["武器與彈藥", "武器", "Weapons"],
	&"weapons_help": ["查看彈藥並切換攜帶中的武器", "弾薬を確認して所持武器を切り替える", "Check ammo and switch equipped weapons"],
	&"mods": ["改裝", "改造", "Mods"],
	&"mods_help": ["改裝攜帶中的武器（目前 ¥%d）", "所持武器を改造する（残高 ¥%d）", "Upgrade carried weapons (¥%d available)"],
	&"cyberware": ["義體", "義体", "Cyberware"],
	&"cyberware_help": ["解鎖並裝備義體能力（目前 ¥%d）", "義体を解放して装備する（残高 ¥%d）", "Unlock and equip cyberware (¥%d available)"],
	&"story": ["劇情道具", "物語", "Story"],
	&"story_help": ["回顧旅途中取得的關鍵物品", "入手した重要アイテムを確認する", "Review key items collected on this run"],
	&"story_collection": ["回顧關鍵物品、文件與錄音（%d／%d）", "重要アイテム、文書、録音を確認する（%d／%d）", "Review key items, documents and recordings (%d/%d)"],
	&"status": ["角色狀態", "状態", "Status"],
	&"status_help": ["查看凜的狀態與本輪紀錄", "リンの状態と今回の記録を確認する", "View Rin’s status and run statistics"],
	&"pawn": ["典當", "質入れ", "Pawn"],
	&"pawn_help": ["典當補給並加息贖回（目前 ¥%d，當票 %d／%d）", "補給品を質に入れ、利息を払って買い戻す（残高 ¥%d、質札 %d／%d）", "Pawn or redeem supplies with interest (¥%d, %d/%d tickets)"],
	&"stock": ["補給", "補給", "Stock"],
	&"stock_help": ["購買補給（目前 ¥%d）", "補給品を購入する（残高 ¥%d）", "Buy supplies (¥%d available)"],
}


static func get_text(key: StringName) -> String:
	var language_index := StoryLocale.LANGUAGES.find(Story.language)
	var variants: Array = TEXT[key]
	return variants[language_index] if language_index >= 0 and language_index < variants.size() else variants[0]
