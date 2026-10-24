extends RefCounted
## Real catalog entries, independent of acquisition or chapter fixtures.
static func run(s: TestSuite) -> void:
	var page := StoryItemsPage.new()
	for id: StringName in [&"ch1_market_summary", &"ch3_report_p17", &"ch3_tour_card"]:
		var item := StoryItems.find(id)
		s.check(item != null and not item.body_text().is_empty() and not page._entry_for(item).action_label.is_empty(), "key document offers its complete authored text: " + String(id))
	var ordinary: StoryItemData
	for item: StoryItemData in StoryItems.catalog():
		if not item.is_collectible() and item.body_text().is_empty():
			ordinary = item
			break
	s.check(ordinary != null and page._entry_for(ordinary).action_label.is_empty(), "a key item without a body keeps its original view-only behavior")
	page.free()
