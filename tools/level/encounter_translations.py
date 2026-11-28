"""Localized encounter names and lock messages for chapter-one encounters and arena gates (en, ja)."""

TEXTS = {
    "競技場閘門": ("Arena gate", "アリーナのゲート"),
    "遭遇：路障": ("Encounter: Blockade", "遭遇：封鎖地点"),
    "收帳人正在前方搜查，小心。": ("The collectors are searching up ahead.", "前方で取り立て屋が捜索している。"),
    "前方的追兵清掉了。": ("The pursuers ahead are down.", "前方の追手を排除した。"),
    "遭遇：街心": ("Encounter: Plaza", "遭遇：広場"),
    "廣場有收帳人巡邏，留意增援。": ("Collectors are patrolling the plaza. Watch for reinforcements.", "広場を取り立て屋が巡回中。増援に注意。"),
    "廣場暫時安全了。": ("The plaza is clear for now.", "広場はひとまず安全だ。"),
    "遭遇：保險箱守衛": ("Encounter: Safe guards", "遭遇：金庫の護衛"),
    "有人看守保險箱，小心。": ("The safe is guarded. Stay sharp.", "金庫には見張りがいる。気をつけて。"),
    "保險箱安全了": ("The safe is clear.", "金庫の周囲は安全だ。"),
    "遭遇：上層走道": ("Encounter: Upper walkway", "遭遇：上層通路"),
    "走道有守衛，留意增援。": ("Guards on the walkway. Watch for reinforcements.", "通路に警備兵がいる。増援に注意。"),
    "走道暫時安全了。": ("The walkway is clear for now.", "通路はひとまず安全だ。"),
}


def localized(text):
    """{"en": ..., "ja": ...} for a Chinese encounter text, or None when it has no translation yet."""
    pair = TEXTS.get(text)
    return {"en": pair[0], "ja": pair[1]} if pair else None
