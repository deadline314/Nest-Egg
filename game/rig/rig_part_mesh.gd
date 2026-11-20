class_name RigPartMesh
extends Polygon2D
## 可彎曲的肢體零件（NE-204）：一張連續的貼圖鋪在一個小網格上，靠近關節的頂點同時跟著兩根骨頭走，
## 膝與肘彎起來時外側被拉開、內側被壓攏，輪廓是連續的曲線而不是兩塊剛體的直線切口。
##
## 做法（骨架動畫的標準線性混合蒙皮，加上限長修正）：
##  - 零件本來掛在骨頭 A 上；關節另一側的骨頭 P（A 的子骨頭＝膝、肘的下半，或 A 的父骨頭＝上半）叫夥伴骨頭。
##  - 關節附近一段（zone）的頂點依離關節的距離得到權重 w（關節正中 0.5），位置在「跟著 A」與「跟著 P」之間混合。
##  - 混合會讓關節處變窄（骨頭夾角越大越窄），所以把頂點到肢體軸線的距離修正回原本長度（保持肢體粗細）。
##  - 上下兩塊零件用同一套權重曲線，重疊的地方互相遮住，接縫看不到。
## 只有靠近關節的頂點每格重算，其餘頂點固定；骨頭沒動就整個跳過。發光層（glow）共用同一份頂點。

## 欄數（寬度方向的格線，含兩側邊緣）；肢體很窄，三條就夠。
const COLUMNS := 3
## 關節附近每半段再切幾列（越多越圓，也越耗）。
const ZONE_ROWS := 3
## 粗細修正的程度：0＝純線性混合（關節縮腰），1＝完全維持原本粗細。實測 1.0 的膝與肘最像真的腿（內側的輕微折疊被貼圖本身的皺褶蓋住）。
static var volume_keep := 1.0
## 骨頭相對變換小於這個值就當作沒動。
const EPSILON := 0.0005
const WIDTH_EPSILON := 0.0001
const ROW_WIDTH_GUARD := 0.002

## 重算過幾次頂點（測試用：骨頭沒動時不該增加）。
var deform_count := 0
var pivot_offset := Vector2.ZERO  ## 對應 Sprite2D 的 offset（－支點，貼圖像素）

var _self_bone: Bone2D
var _partner: Bone2D
var _partner_is_child := true
var _partner_direction := 1
var _self_rest := Vector2.ZERO
var _partner_rest := Vector2.ZERO
var _axis_x := 0.0
var _rest_local := PackedVector2Array()
var _triangles := PackedInt32Array()
var _zone_rows := PackedInt32Array()
var _zone_offsets := PackedVector2Array()  ## X offsets shared by every joint row.
var _zone_row_data := PackedVector2Array()  ## (height in bone space, blend weight)
var _row_width_floor := ROW_WIDTH_GUARD
var _to_local := Transform2D.IDENTITY
var _last := Transform2D.IDENTITY
var _root_partner: Bone2D
var _root_radius := 0.0
var _root_origin := Vector2.ZERO
var _root_indices := PackedInt32Array()
var _root_points := PackedVector2Array()
var _root_weights := PackedFloat32Array()
var _last_root := Transform2D.IDENTITY
var _glow: Polygon2D
var _deformed := PackedVector2Array()
var _min_width_ratio := 1.0
var _width_stale := false
var _folds := 0
var _folds_stale := false  ## 折疊數只在有人問（測試、稽核）時才算，每格動畫不付這個成本


## 這個零件在骨頭 A 的空間裡佔的垂直範圍（上緣、下緣）；node_transform 是零件節點對骨頭的變換（位置、縮放，沒有旋轉）。
static func vertical_span(size: Vector2, pivot: Vector2, node_transform: Transform2D) -> Vector2:
	var top: float = (node_transform * Vector2(0.0, -pivot.y)).y
	var bottom: float = (node_transform * Vector2(0.0, size.y - pivot.y)).y
	return Vector2(top, bottom)


## 這個零件要不要做成網格：它得碰到關節附近（zone）才有意義，旋轉過的零件維持剛體。
## partner_is_child：關節在零件下緣（離骨頭原點 joint_y 處）；否則關節在骨頭原點（零件上緣）。
static func reaches_joint(span: Vector2, joint_y: float, zone: float, partner_is_child: bool) -> bool:
	if partner_is_child:
		return span.y >= joint_y - zone * 0.5
	return span.x <= joint_y + zone * 0.5


## 建立網格。回傳 false 代表資料不合理（沒有東西可建），呼叫端改用一般的 Sprite2D。
## node_transform：零件節點的位置與縮放（已設到節點上）；joint_y：關節離骨頭原點的距離（骨頭 A 空間的 y）；zone：混合半徑（世界像素）。
func setup(p_texture: Texture2D, size: Vector2, pivot: Vector2, self_bone: Bone2D, partner: Bone2D, partner_is_child: bool, self_rest: Vector2, partner_rest: Vector2, zone: float, direction := 0, root_partner: Bone2D = null, root_radius := 0.0, root_origin := Vector2.ZERO) -> bool:
	if p_texture == null or size.x < 2.0 or size.y < 2.0 or zone <= 0.0 or self_bone == null or partner == null:
		return false
	if root_partner != null and (root_radius <= 0.0 or self_bone.get_parent() != root_partner):
		return false
	texture = p_texture
	pivot_offset = -pivot
	_self_bone = self_bone
	_partner = partner
	_partner_is_child = partner_is_child
	_partner_direction = direction if direction != 0 else (1 if partner_is_child else -1)
	_root_partner = root_partner
	_root_radius = root_radius
	_root_origin = root_origin
	_self_rest = self_rest
	_partner_rest = partner_rest
	_axis_x = partner_rest.x if partner_is_child else 0.0
	var node_transform := Transform2D(0.0, scale, 0.0, position)
	_to_local = node_transform.affine_inverse()
	var joint_y := partner_rest.y if partner_is_child else 0.0
	# 列：上下緣加上關節附近的幾列（本地貼圖座標的 v，由上到下）。
	var span := vertical_span(size, pivot, node_transform)
	var rows: Array[float] = [0.0, size.y]
	# Upward waist bends need fewer rows than the sharply bent knee/elbow.
	var zone_rows := 2 if _partner_direction != (1 if partner_is_child else -1) else ZONE_ROWS
	var step := zone / float(zone_rows)
	for i in range(-zone_rows, zone_rows + 1):
		var y := joint_y + float(i) * step
		if y <= span.x + 0.001 or y >= span.y - 0.001:
			continue
		rows.append(((y - position.y) / scale.y) + pivot.y)
	if _root_partner != null:
		for i in range(0, ZONE_ROWS + 1):
			var y := root_radius * float(i) / float(ZONE_ROWS)
			if y > span.x + 0.001 and y < span.y - 0.001:
				rows.append(((y - position.y) / scale.y) + pivot.y)
	rows.sort()
	var uv := PackedVector2Array()
	_rest_local = PackedVector2Array()
	_zone_rows = PackedInt32Array()
	_zone_offsets = PackedVector2Array()
	_row_width_floor = ROW_WIDTH_GUARD
	_zone_row_data = PackedVector2Array()
	_root_indices = PackedInt32Array()
	_root_points = PackedVector2Array()
	_root_weights = PackedFloat32Array()
	var previous_row := -INF
	for row in rows:
		if is_equal_approx(row, previous_row):
			continue
		previous_row = row
		# A row has one Y value because the mesh setup transform has no rotation or shear.
		var row_y := (node_transform * (Vector2(0.0, row) - pivot)).y
		var weight := _weight_at(row_y, joint_y, zone, _partner_direction > 0)
		if weight > 0.0:
			_zone_rows.append(_rest_local.size())
			_zone_row_data.append(Vector2(row_y, weight))
		var store_offsets := weight > 0.0 and _zone_offsets.is_empty()
		for c in COLUMNS:
			var u := size.x * float(c) / float(COLUMNS - 1)
			uv.append(Vector2(u, row))
			var local := Vector2(u, row) - pivot
			_rest_local.append(local)
			var in_a: Vector2 = node_transform * local
			if store_offsets:
				var offset := Vector2(in_a.x - _axis_x, 0.0)
				_zone_offsets.append(offset)
				var width := absf(offset.x)
				if width > 0.0:
					_row_width_floor = maxf(_row_width_floor, 2.0 * WIDTH_EPSILON / width if width > WIDTH_EPSILON else INF)
			if _root_partner != null and in_a.y < _root_radius:
				var t := clampf(in_a.y / _root_radius, 0.0, 1.0)
				_root_indices.append(_rest_local.size() - 1)
				_root_points.append(in_a)
				_root_weights.append(1.0 - t * t * (3.0 - 2.0 * t))
	_triangles = PackedInt32Array()
	for r in (_rest_local.size() / COLUMNS) - 1:
		for c in COLUMNS - 1:
			var i0 := r * COLUMNS + c
			var i1 := i0 + 1
			var i2 := i0 + COLUMNS
			var i3 := i2 + 1
			_triangles.append_array([i0, i1, i3, i0, i3, i2])
	self.uv = uv
	polygon = _rest_local
	polygons = _split_triangles(_triangles)
	_deformed = _rest_local.duplicate()
	_last = Transform2D.IDENTITY
	_last_root = Transform2D.IDENTITY
	_min_width_ratio = 1.0
	_width_stale = false
	return true


## 發光層：同樣的網格與貼圖座標，加法混合；呼叫端提供材質。
func set_glow(glow_texture: Texture2D, glow_material: Material, intensity: Color) -> void:
	if glow_texture == null:
		return
	_glow = Polygon2D.new()
	_glow.name = "Glow"
	_glow.texture = glow_texture
	_glow.uv = uv
	_glow.polygon = _rest_local
	_glow.polygons = polygons
	_glow.light_mask = 0
	_glow.material = glow_material
	_glow.self_modulate = intensity
	add_child(_glow)


## 依兩根骨頭現在的相對姿勢重算關節附近的頂點。骨頭沒動就不做事；零件看不到時也不做（顯示時自然補算）。
func refresh() -> void:
	if not visible or _self_bone == null:
		return
	var follow := _follow_transform()
	var has_root := _root_partner != null
	var root_follow := _self_bone.transform.affine_inverse() * Transform2D(0.0, _root_origin) if has_root else Transform2D.IDENTITY
	if _same(follow, _last) and (not has_root or _same(root_follow, _last_root)):
		return
	_last = follow
	if has_root:
		_last_root = root_follow
	_deform(follow, root_follow)
	polygon = _deformed
	if _glow != null:
		_glow.polygon = _deformed


func _follow_transform() -> Transform2D:
	if _partner_is_child:
		return _partner.transform * Transform2D(0.0, -_partner_rest)
	return _self_bone.transform.affine_inverse() * Transform2D(0.0, _self_rest)


func _deform(follow: Transform2D, root_follow: Transform2D) -> void:
	deform_count += 1
	_deformed = _rest_local.duplicate()
	var along_x := follow.x
	for row in _zone_rows.size():
		var first := _zone_rows[row]
		var row_data := _zone_row_data[row]
		var w := row_data.y
		var axis := Vector2(_axis_x, row_data.x)
		var moved_axis: Vector2 = axis.lerp(follow * axis, w)
		var blended := Vector2.RIGHT.lerp(along_x, w)
		var length := blended.length()
		if length <= _row_width_floor:
			_deform_narrow_row(first, moved_axis, along_x, w)
			continue
		var direction := blended * lerpf(1.0, 1.0 / length, volume_keep)
		var index := first
		for offset in _zone_offsets:
			_deformed[index] = _to_local * (moved_axis + direction * offset.x)
			index += 1
	_width_stale = true
	_folds_stale = true
	if _root_indices.is_empty():
		return
	# The root edge follows its rigid parent completely; fade to the limb below it.
	# Rotate the row width instead of averaging opposing vectors at large hip angles.
	var last_y := INF
	var moved_axis := Vector2.ZERO
	var row_direction := Vector2.RIGHT
	var angle := root_follow.get_rotation()
	for k in _root_indices.size():
		var v := _root_points[k]
		var w := _root_weights[k]
		if not is_equal_approx(v.y, last_y):
			last_y = v.y
			var axis := Vector2(0.0, v.y)
			moved_axis = axis.lerp(root_follow * axis, w)
			row_direction = Vector2.from_angle(angle * w)
		_deformed[_root_indices[k]] = _to_local * (moved_axis + row_direction * v.x)


## Near a collapsed row, retain per-column precision at the width cutoff.
func _deform_narrow_row(first: int, axis: Vector2, along_x: Vector2, weight: float) -> void:
	var index := first
	for offset in _zone_offsets:
		var moved: Vector2 = offset.lerp(along_x * offset.x, weight)
		var length := moved.length()
		var width := absf(offset.x)
		if length > WIDTH_EPSILON and width > WIDTH_EPSILON:
			moved *= lerpf(1.0, width / length, volume_keep)
		_deformed[index] = _to_local * (axis + moved)
		index += 1


## 目前的網格有幾個三角形被翻面（折疊）。彎到 90° 以上時內側一定會有幾個（關節的內側被壓攏，貼圖重疊在一起像皺褶）。
func fold_count() -> int:
	if _folds_stale:
		_folds = _count_folds()
		_folds_stale = false
	return _folds


## 折疊的三角形佔全部的比例；稽核用它判斷網格有沒有爛掉（格擋與蹲到底時最多約 35%）。
func fold_fraction() -> float:
	return float(fold_count()) / maxf(1.0, float(triangle_count()))


## 關節附近最窄處相對靜止寬度的比例（混合後、修正前）；越接近 1 越沒有縮腰。
func width_ratio() -> float:
	if _width_stale:
		_width_stale = false
		_min_width_ratio = 1.0
		var along_x := _last.x
		for row_data in _zone_row_data:
			for offset in _zone_offsets:
				var wanted := absf(offset.x)
				var length := offset.lerp(along_x * offset.x, row_data.y).length()
				if length > WIDTH_EPSILON and wanted > WIDTH_EPSILON:
					_min_width_ratio = minf(_min_width_ratio, length / wanted)
	return _min_width_ratio


func triangle_count() -> int:
	return _triangles.size() / 3


func vertex_count() -> int:
	return _rest_local.size()


## 目前的頂點（本地貼圖座標）；測試與稽核用。
func deformed_vertices() -> PackedVector2Array:
	return _deformed


## 靜止姿勢的頂點。
func rest_vertices() -> PackedVector2Array:
	return _rest_local


func _count_folds() -> int:
	var folds := 0
	for t in range(0, _triangles.size(), 3):
		var a := _deformed[_triangles[t]]
		var b := _deformed[_triangles[t + 1]]
		var c := _deformed[_triangles[t + 2]]
		var rest_a := _rest_local[_triangles[t]]
		var rest_b := _rest_local[_triangles[t + 1]]
		var rest_c := _rest_local[_triangles[t + 2]]
		var now := (b - a).cross(c - a)
		var before := (rest_b - rest_a).cross(rest_c - rest_a)
		if now * before < 0.0:
			folds += 1
	return folds


static func _weight_at(y: float, joint_y: float, zone: float, partner_is_child: bool) -> float:
	var t := clampf((y - (joint_y - zone)) / (2.0 * zone), 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var w := s if partner_is_child else 1.0 - s
	# 關節遠端的頂點完全不動（不需要每格重算）。
	return w if w > 0.001 else 0.0


static func _same(a: Transform2D, b: Transform2D) -> bool:
	return a.origin.is_equal_approx(b.origin) and absf(a.x.x - b.x.x) < EPSILON and absf(a.x.y - b.x.y) < EPSILON \
			and absf(a.y.x - b.y.x) < EPSILON and absf(a.y.y - b.y.y) < EPSILON


static func _split_triangles(indices: PackedInt32Array) -> Array:
	var result: Array = []
	for t in range(0, indices.size(), 3):
		result.append(PackedInt32Array([indices[t], indices[t + 1], indices[t + 2]]))
	return result
