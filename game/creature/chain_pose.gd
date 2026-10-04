class_name ChainPose
extends RefCounted
## 骨頭鏈的姿勢數學（純函式，方便單獨測試）。
## 角度採骨頭慣例：0＝朝下（+y），正值順時針（Godot 的 rotation）。


## 方向向量的骨頭角度。
static func heading_of(direction: Vector2) -> float:
	return atan2(-direction.x, direction.y)


static func direction_of(heading: float) -> Vector2:
	return Vector2(-sin(heading), cos(heading))


## 讓 n 節等長的鏈（每節 seg_len）從 root 彎成一道弧，尖端落在 root + chord：
## 回傳每根骨頭「相對父骨頭」的旋轉（第 0 根是相對骨架的絕對旋轉）。弧彎向 bulge 方向那一側（膝蓋抬起的方向）。
## 弦比整條鏈還長時拉直朝向目標（碰不到）。
static func arc(chord: Vector2, seg_len: float, n: int, bulge: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var length := seg_len * float(n)
	var distance := chord.length()
	var chord_heading := heading_of(chord) if distance > 0.001 else 0.0
	var theta := 0.0
	if distance < length * 0.999 and n > 1:
		theta = _solve_turn(distance / length, n)
	var side := 1.0
	if theta > 0.0:
		var normal := chord.normalized().rotated(-PI * 0.5)
		side = 1.0 if bulge.dot(normal) >= 0.0 else -1.0
	var step := side * theta / float(n)
	out[0] = chord_heading - side * theta * 0.5 + step * 0.5
	for i in range(1, n):
		out[i] = step
	return out


## 多邊形鏈的弦長比 d/L = sin(θ/2) / (n sin(θ/2n)) 對應的總轉角 θ（0～2π，二分法）。
static func _solve_turn(ratio: float, n: int) -> float:
	var low := 0.0
	var high := TAU * 0.98
	for i in 18:
		var mid := (low + high) * 0.5
		var r := sin(mid * 0.5) / (float(n) * sin(mid / (2.0 * float(n))))
		if r > ratio:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


## 鏈尖端相對根部的位置（驗證 arc 用）：rotations 同 arc 的輸出。
static func tip_of(rotations: PackedFloat32Array, seg_len: float) -> Vector2:
	var heading := 0.0
	var at := Vector2.ZERO
	for r in rotations:
		heading += r
		at += direction_of(heading) * seg_len
	return at
