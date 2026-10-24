extends RefCounted
## Payment status and tomorrow's terms must remain distinct from the ledger balance.
static func run(s: TestSuite) -> void:
	var language := Story.language
	Story.language = "en"
	var body := StoryItems.find(&"ch1_market_summary").body_text().to_lower()
	s.check(body.contains("not proof of payment"), "M17 English warns that the page cannot establish payment")
	s.check(body.contains("extra pay") and body.contains("tomorrow morning"), "M17 English preserves the extra reward and next-morning explanation")
	Story.language = language
