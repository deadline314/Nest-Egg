class_name LampStyle
extends Resource
## 場景燈的風格：一個光影區段裡的燈長什麼樣子（顏色、光池大小、會不會閃、有沒有壞掉）。
## 每盞燈用自己的位置當種子挑顏色與狀態，所以同一關每次進來都一樣。

@export var colors: PackedColorArray = PackedColorArray([Color(0.35, 0.88, 1.0)])
@export_range(0.0, 4.0, 0.05) var energy: float = 1.5
## 光池半徑（像素）。
@export_range(40.0, 400.0, 5.0) var radius: float = 190.0
## 每影格開始閃爍的機率（0 = 不閃）。
@export_range(0.0, 0.2, 0.001) var flicker_chance: float = 0.008
## 整盞壞掉不亮的比例（0~1）。
@export_range(0.0, 1.0, 0.05) var dead_chance: float = 0.0
## 亮度脈動的頻率（Hz，0 = 不脈動）：警示燈用。
@export_range(0.0, 4.0, 0.05) var pulse_hz: float = 0.0
## 這一區可以用的燈具款式（LampFixtures 的 id）。相鄰的燈輪流換款；某一盞周圍裝不上這些款式時改用備用款。
@export var fixtures: PackedStringArray = PackedStringArray()
## 燈具的光色裡混進多少這一區的顏色（0＝完全是燈具自己的顏色，1＝完全是這一區的顏色）。
## 一般的區域只帶一點；靠彩色燈泡營造氣氛的地方（復原館、市集）調高，燈具的發光部位會跟著染色。
@export_range(0.0, 1.0, 0.01) var fixture_tint: float = 0.18


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if colors.is_empty():
		problems.append("燈的風格沒有任何顏色")
	if energy < 0.0 or radius <= 0.0:
		problems.append("燈的能量不能是負的、半徑必須大於 0")
	if fixture_tint < 0.0 or fixture_tint > 1.0:
		problems.append("燈具染色的比例要在 0 到 1 之間")
	if flicker_chance < 0.0 or dead_chance < 0.0 or dead_chance > 1.0 or pulse_hz < 0.0:
		problems.append("燈的閃爍機率、壞掉比例或脈動頻率超出範圍")
	for fixture: String in fixtures:
		if LampFixtures.fixture(StringName(fixture)).is_empty():
			problems.append("燈的風格用了不存在的燈具款式：%s" % fixture)
	return problems


func color_for(rng: RandomNumberGenerator) -> Color:
	return colors[rng.randi() % colors.size()] if not colors.is_empty() else Color.WHITE
