extends RefCounted
## 章節敵人名單的跨章規則（NE-477；data/combat/chapter_rosters.json）。
## 使用者的原話（NE-97，2026-10-03～04）：「跨章最多一至兩種重複敵人」，讓每章有自己的敵人生態。
## - 正式名單（enemies＋reserved）裡，一種敵人出現在兩章以上，必須在頂層 shared 明寫：哪一種、哪兩章、為什麼兩章都合理。
## - 任兩章之間最多共用兩種。
## - 每章（有敵人的）至少要有一種只屬於自己的敵人。
## - 共用的不能是該章的主力：該章擺放最多的敵人不能是共用的。
## demo_enemies 是舊開發關卡的名單，不算進跨章規則。

const MAX_SHARED_PER_PAIR := 2


## roster：整份 JSON；placements：{章節: {敵人 id: 擺放數}}（沒有就當作 0）。回傳問題清單，空的代表通過。
static func problems(roster: Dictionary, placements: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var chapters: Dictionary = roster.get("chapters", {})
	var owners := {}
	for chapter: String in chapters:
		var entry: Dictionary = chapters[chapter]
		for enemy: String in (entry.get("enemies", []) as Array) + (entry.get("reserved", []) as Array):
			if not owners.has(enemy):
				owners[enemy] = []
			if not (owners[enemy] as Array).has(chapter):
				(owners[enemy] as Array).append(chapter)
	var declared := {}
	var pair_counts := {}
	for share: Variant in roster.get("shared", []):
		if typeof(share) != TYPE_DICTIONARY:
			found.append("shared 的每一筆要是物件：%s" % str(share))
			continue
		var enemy := str((share as Dictionary).get("enemy", ""))
		var pair: Array = (share as Dictionary).get("chapters", [])
		var reason := str((share as Dictionary).get("reason", "")).strip_edges()
		if enemy.is_empty() or pair.size() != 2 or pair[0] == pair[1]:
			found.append("shared 要寫一種敵人與兩個不同的章節：%s" % str(share))
			continue
		if reason.is_empty():
			found.append("共用的 %s 沒有寫原因" % enemy)
		for chapter: Variant in pair:
			if not chapters.has(str(chapter)):
				found.append("共用的 %s 寫了不存在的章節 %s" % [enemy, chapter])
			elif not (owners.get(enemy, []) as Array).has(str(chapter)):
				found.append("共用的 %s 不在 %s 的名單裡" % [enemy, chapter])
		var key := _pair_key(str(pair[0]), str(pair[1]))
		declared[enemy] = key
		pair_counts[key] = int(pair_counts.get(key, 0)) + 1
	for key: String in pair_counts:
		if int(pair_counts[key]) > MAX_SHARED_PER_PAIR:
			found.append("%s 之間共用了 %d 種敵人（最多 %d 種）" % [key, pair_counts[key], MAX_SHARED_PER_PAIR])
	for enemy: String in owners:
		var list: Array = owners[enemy]
		if list.size() <= 1:
			continue
		if list.size() > 2:
			found.append("%s 出現在 %d 章（共用最多兩章）：%s" % [enemy, list.size(), ", ".join(PackedStringArray(list))])
		elif declared.get(enemy, "") != _pair_key(str(list[0]), str(list[1])):
			found.append("%s 同時在 %s 與 %s，但沒有在 shared 寫明" % [enemy, list[0], list[1]])
	for chapter: String in chapters:
		var own := 0
		var listed: Array = (chapters[chapter] as Dictionary).get("enemies", [])
		for enemy: String in listed:
			if not declared.has(enemy):
				own += 1
		if not listed.is_empty() and own == 0:
			found.append("%s 沒有只屬於自己的敵人" % chapter)
		var counts: Dictionary = placements.get(chapter, {})
		var top_own := 0
		var top_shared := 0
		var top_shared_id := ""
		for enemy: String in counts:
			var count := int(counts[enemy])
			if declared.has(enemy):
				if count > top_shared:
					top_shared = count
					top_shared_id = enemy
			else:
				top_own = maxi(top_own, count)
		if top_shared > 0 and top_shared >= top_own:
			found.append("%s 的主力是共用的 %s（擺放 %d 隻，自己的敵人最多 %d 隻）" % [chapter, top_shared_id, top_shared, top_own])
	return found


static func _pair_key(a: String, b: String) -> String:
	return "%s+%s" % ([a, b] if a < b else [b, a])
