class_name ChainMesh
extends RefCounted
## 骨頭鏈的網格變形資料：一張連續貼圖沿骨頭鏈切成密格（每節 2 排、3 欄頂點），頂點依位置分給相鄰兩根骨頭權重。
## 拓樸（面與權重）只和骨頭節數有關，依節數快取，同種生物重複生成不重算。
## 觸手（ChainCreature）與蠕行（WormCreature）共用。

const COLUMNS := 3
const ROWS_PER_SEGMENT := 2

## 節數 -> {polys: Array, weights: Array[PackedFloat32Array]}
static var _topology: Dictionary = {}


static func rows_for(segments: int) -> int:
	return segments * ROWS_PER_SEGMENT + 1


## 頂點與 UV：從 origin 沿 angle 方向（骨頭慣例：0＝朝下）長 seg_len * segments、寬 width；mirror 讓貼圖左右翻轉。
static func build_geometry(tex_size: Vector2, segments: int, width: float, seg_len: float, origin: Vector2, angle: float, mirror: bool) -> Dictionary:
	var rows := rows_for(segments)
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var rot := Transform2D(angle, Vector2.ZERO)
	var half := width * 0.5
	var total := seg_len * float(segments)
	for r in rows:
		var t := float(r) / float(rows - 1)
		for c in COLUMNS:
			var u := float(c) / float(COLUMNS - 1)
			verts.append(origin + rot * Vector2(lerpf(-half, half, u), t * total))
			uvs.append(Vector2((1.0 - u if mirror else u) * tex_size.x, t * tex_size.y))
	return {"verts": verts, "uvs": uvs}


## 面與每根骨頭的權重（依節數快取；回傳的陣列是共用的，不要修改）。
static func topology(segments: int) -> Dictionary:
	if _topology.has(segments):
		return _topology[segments]
	var rows := rows_for(segments)
	var polys: Array = []
	for r in rows - 1:
		for c in COLUMNS - 1:
			var a := r * COLUMNS + c
			polys.append(PackedInt32Array([a, a + 1, a + COLUMNS + 1, a + COLUMNS]))
	var weights: Array[PackedFloat32Array] = []
	for i in segments:
		var w := PackedFloat32Array()
		w.resize(rows * COLUMNS)
		weights.append(w)
	for r in rows:
		var t := float(r) / float(rows - 1) * float(segments)  # 沿鏈的位置，單位＝節
		var k := mini(int(floor(t)), segments - 1)
		var f := t - float(k)
		for c in COLUMNS:
			var v := r * COLUMNS + c
			if k + 1 < segments:
				weights[k][v] = 1.0 - f
				weights[k + 1][v] = f
			else:
				weights[k][v] = 1.0
	var result := {"polys": polys, "weights": weights}
	_topology[segments] = result
	return result
