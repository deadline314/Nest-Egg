extends RefCounted
## Pure authored geometry; the original cold Main probe separately verifies startup.
static func run(suite: TestSuite) -> void:
	var layout := LevelLayout.new()
	layout.tile_size = 16
	layout.width = 4
	layout.height = 4
	layout.rows = PackedStringArray(["....", "=...", "....", "####"])
	var level := Level.new()
	level._layout = layout
	suite.check(level.authored_floor_below(Vector2(8, 0)) == Vector2(8, 16), "original map query finds the first platform surface")
	suite.check(level.authored_floor_below(Vector2(8, 20)) == Vector2(8, 48), "a ray beginning inside a platform continues to the next authored floor")
	suite.check(not level.authored_floor_below(Vector2(8, 0), 15).is_finite(), "authored map fallback preserves the original query distance")
	suite.check(not level.authored_floor_below(Vector2(80, 0)).is_finite(), "missing authored floor never becomes a fake boss-height surface")
	level.position = Vector2(10, 20)
	level.scale = Vector2(2, 2)
	suite.check(level.authored_floor_below(Vector2(26, 60), 60) == Vector2(26, 116), "map fallback keeps world coordinates under original level translation and scale")
	level.scale = Vector2.ZERO
	suite.check(not level.authored_floor_below(Vector2(26, 60)).is_finite(), "a singular map transform fails without attempting an inverse")
	level.free()
