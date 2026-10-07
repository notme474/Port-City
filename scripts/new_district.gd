extends Node3D
## 东岸新区（Vice Beach）：用项目自带 Kenney CC0 城市套件程序化拼出的完整新城区。
## 选址主城东侧空地 x≈380~640 / z≈-220~40，西侧接现有 x≈333 南北主干道。
## 每栋楼运行时按合并 AABB 自动生成盒碰撞；道路仅视觉（地形已提供地面碰撞）。

const GROUND_Y := 5.95
const CO := "res://Kenney 城市套件·商业区/Models/GLB format/"
const SU := "res://Kenney 城市套件·郊区/Models/GLB format/"
const BUILD_SCALE := 10.0

# 新区网格
const ORIGIN_X := 380.0
const ORIGIN_Z := -220.0
const COLS := 5
const ROWS := 4
const PITCH := 64.0          # 街区中心间距（建筑带 52 + 马路 12）
const ROAD_W := 14.0

var _rng := RandomNumberGenerator.new()
var _root: Node3D
var _roads: Node3D
var _buildings: Node3D
var _decor: Node3D
var _entered := false

const TOWERS := ["建筑_摩天楼_a.glb", "建筑_摩天楼_b.glb", "建筑_摩天楼_c.glb",
	"建筑_摩天楼_d.glb", "建筑_摩天楼_e.glb"]
const MID := ["建筑_a.glb", "建筑_b.glb", "建筑_c.glb", "建筑_d.glb", "建筑_e.glb",
	"建筑_f.glb", "建筑_g.glb", "建筑_h.glb", "建筑_i.glb", "建筑_j.glb",
	"建筑_k.glb", "建筑_l.glb", "建筑_m.glb", "建筑_n.glb"]
const LOW := ["低精度建筑_a.glb", "低精度建筑_b.glb", "低精度建筑_c.glb",
	"低精度建筑_d.glb", "低精度建筑_e.glb", "低精度建筑_f.glb", "低精度建筑_g.glb",
	"低精度建筑_h.glb", "低精度建筑_i.glb", "低精度建筑_j.glb", "低精度建筑_k.glb",
	"低精度建筑_l.glb", "低精度建筑_m.glb", "低精度建筑_n.glb",
	"低精度建筑_宽_a.glb", "低精度建筑_宽_b.glb"]
const HOUSES := ["building-type-a.glb", "building-type-b.glb", "building-type-c.glb",
	"building-type-d.glb", "building-type-e.glb", "building-type-f.glb",
	"building-type-g.glb", "building-type-h.glb", "building-type-i.glb",
	"building-type-j.glb", "building-type-k.glb", "building-type-l.glb",
	"building-type-m.glb", "building-type-n.glb", "building-type-o.glb",
	"building-type-p.glb", "building-type-q.glb", "building-type-r.glb",
	"building-type-s.glb", "building-type-t.glb", "building-type-u.glb"]

func _ready() -> void:
	_rng.seed = 20261007
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_root = Node3D.new()
	_root.name = "东岸新区"
	add_child(_root)
	_roads = _mk_group("道路")
	_buildings = _mk_group("建筑")
	_decor = _mk_group("装饰")
	_build_roads()
	_build_blocks()
	_build_suburbs()
	_build_gate()
	_build_trigger()

func _mk_group(nm: String) -> Node3D:
	var g := Node3D.new()
	g.name = nm
	_root.add_child(g)
	return g

func _gy(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -10.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else GROUND_Y

# ---------- 道路：深灰薄片横竖网格 + 中线 ----------
func _build_roads() -> void:
	var w := COLS * PITCH
	var d := ROWS * PITCH
	var cx := ORIGIN_X + w * 0.5 - PITCH * 0.5
	var cz := ORIGIN_Z + d * 0.5 - PITCH * 0.5
	var road_mat := _mat(Color(0.11, 0.11, 0.13), 0.95)
	var line_mat := _mat(Color(0.85, 0.78, 0.35), 0.7)
	# 竖向马路（COLS+1 条）
	for i in COLS + 1:
		var x := ORIGIN_X - PITCH * 0.5 + i * PITCH
		_slabs(x, cx, cz, ROAD_W, d + PITCH, road_mat, line_mat, true)
	# 横向马路（ROWS+1 条）
	for j in ROWS + 1:
		var z := ORIGIN_Z - PITCH * 0.5 + j * PITCH
		_slabs(z, cx, cz, w + PITCH, ROAD_W, road_mat, line_mat, false)

## 一条马路：路面薄片 + 虚线中线（dir_vert=true 表示南北向）
func _slabs(coord: float, _cx: float, cz: float, along_w: float, along_d: float,
		road_mat: Material, line_mat: Material, vert: bool) -> void:
	var ground := GROUND_Y
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# vert：road 沿 z 方向长（x 宽 ROAD_W）；横：沿 x
	if vert:
		bm.size = Vector3(along_w, 0.12, along_d)
		slab.position = Vector3(coord, ground + 0.02, cz)
	else:
		bm.size = Vector3(along_w, 0.12, along_d)
		slab.position = Vector3(_cx, ground + 0.02, coord)
	slab.mesh = bm
	slab.material_override = road_mat
	_roads.add_child(slab)
	# 黄色虚线中线：沿长条方向每 8m 一段 3m
	var length: float = along_d if vert else along_w
	var t := -length * 0.5 + 4.0
	while t < length * 0.5:
		var dash := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.3, 0.04, 3.0) if vert else Vector3(3.0, 0.04, 0.3)
		dash.mesh = dm
		dash.material_override = line_mat
		if vert:
			dash.position = Vector3(coord, ground + 0.09, cz + t)
		else:
			dash.position = Vector3(_cx + t, ground + 0.09, coord)
		_roads.add_child(dash)
		t += 8.0

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

# ---------- 街区建筑 ----------
func _build_blocks() -> void:
	for ci in COLS:
		for rj in ROWS:
			var bx := ORIGIN_X + ci * PITCH
			var bz := ORIGIN_Z + rj * PITCH
			# 核心 2×2（中间两列两行）放摩天楼天际线
			var core := ci >= 2 and ci <= 3 and rj >= 1 and rj <= 2
			var roll := _rng.randf()
			if core and roll < 0.75:
				# 摩天楼居中
				var t: String = TOWERS[_rng.randi_range(0, TOWERS.size() - 1)]
				_place_building(CO + t, bx + _rng.randf_range(-6, 6), bz + _rng.randf_range(-6, 6),
					_rng.randf_range(0, TAU), BUILD_SCALE * _rng.randf_range(1.0, 1.15))
				# 四周矮楼围合
				_ring_low(bx, bz)
			elif roll < 0.12:
				# 街区公园：树 + 花坛
				_build_park(bx, bz)
			else:
				# 普通街区：4 栋沿街楼
				_ring_mid(bx, bz)
			# 街灯（街区四角路口）
			_streetlight(bx - PITCH * 0.5, bz - PITCH * 0.5)

func _ring_mid(bx: float, bz: float) -> void:
	var off := 20.0
	var spots := [
		[bx - off, bz - off], [bx + off, bz - off],
		[bx - off, bz + off], [bx + off, bz + off]]
	for s in spots:
		if _rng.randf() < 0.85:
			var pool: Array = MID if _rng.randf() < 0.5 else LOW
			var f: String = pool[_rng.randi_range(0, pool.size() - 1)]
			_place_building(CO + f, s[0] + _rng.randf_range(-3, 3), s[1] + _rng.randf_range(-3, 3),
				_snap_yaw(s[0] - bx, s[1] - bz), BUILD_SCALE * _rng.randf_range(0.9, 1.1))

func _ring_low(bx: float, bz: float) -> void:
	var off := 21.0
	var spots := [[bx - off, bz], [bx + off, bz], [bx, bz - off], [bx, bz + off]]
	for s in spots:
		if _rng.randf() < 0.8:
			var f: String = LOW[_rng.randi_range(0, LOW.size() - 1)]
			_place_building(CO + f, s[0], s[1],
				_snap_yaw(s[0] - bx, s[1] - bz), BUILD_SCALE)

## 让楼正面朝向街区中心
func _snap_yaw(dx: float, dz: float) -> float:
	# 楼在中心的哪个方向，正面(-Z)朝中心
	return atan2(dx, dz)

func _build_park(bx: float, bz: float) -> void:
	var ground := _gy(bx, bz)
	# 草地
	var grass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(40, 0.1, 40)
	grass.mesh = gm
	var gmat := _mat(Color(0.28, 0.48, 0.22), 0.95)
	grass.material_override = gmat
	grass.position = Vector3(bx, ground + 0.04, bz)
	_decor.add_child(grass)
	# 树 + 花坛
	for i in 7:
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(4, 17)
		var tx := bx + cos(a) * r
		var tz := bz + sin(a) * r
		var tree: String = SU + ("tree-large.glb" if _rng.randf() < 0.5 else "tree-small.glb")
		_place_decor(tree, tx, tz, _rng.randf_range(0, TAU), BUILD_SCALE * _rng.randf_range(0.8, 1.3))
	for i in 3:
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(2, 10)
		_place_decor(SU + "planter.glb", bx + cos(a) * r, bz + sin(a) * r, 0, BUILD_SCALE)

# ---------- 郊区住宅带（新区南缘一排房子 + 车道 + 栅栏 + 树） ----------
func _build_suburbs() -> void:
	var south_z := ORIGIN_Z + (ROWS - 1) * PITCH + PITCH * 0.5 + 26.0
	var n := COLS
	for i in n:
		var hx := ORIGIN_X + i * PITCH + _rng.randf_range(-8, 8)
		var hz := south_z + _rng.randf_range(-4, 4)
		var f: String = HOUSES[_rng.randi_range(0, HOUSES.size() - 1)]
		_place_building(SU + f, hx, hz, PI, BUILD_SCALE * _rng.randf_range(0.9, 1.15))
		# 车道（从马路到房子）
		if _rng.randf() < 0.7:
			_place_decor(SU + "driveway-short.glb", hx, hz - 12.0, 0, BUILD_SCALE)
		# 院子树
		if _rng.randf() < 0.6:
			_place_decor(SU + "tree-small.glb", hx + _rng.randf_range(-12, 12),
				hz + _rng.randf_range(6, 14), 0, BUILD_SCALE)

# ---------- 入口拱门 + 欢迎牌（西接主城 x≈333 大道） ----------
func _build_gate() -> void:
	var gx := ORIGIN_X - PITCH * 0.5
	var gz := ORIGIN_Z + PITCH * 1.5
	var ground := _gy(gx, gz)
	var gate := Node3D.new()
	gate.position = Vector3(gx, ground, gz)
	_decor.add_child(gate)
	var pillar_mat := _mat(Color(0.75, 0.6, 0.32), 0.7)
	var neon_mat := _mat(Color(1.0, 0.3, 0.75), 0.4)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(1.0, 0.3, 0.75)
	neon_mat.emission_energy_multiplier = 2.5
	for sx in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.6, 9.0, 1.6)
		p.mesh = pm
		p.material_override = pillar_mat
		p.position = Vector3(sx * 7.0, 4.5, 0)
		gate.add_child(p)
	var beam := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(15.6, 2.2, 1.0)
	beam.mesh = bm2
	beam.material_override = neon_mat
	beam.position = Vector3(0, 9.2, 0)
	gate.add_child(beam)
	# 拱门碰撞（两根柱）
	for sx in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.6, 9.0, 1.6)
		cs.shape = sh
		cs.position = Vector3(sx * 7.0, 4.5, 0)
		body.add_child(cs)
		gate.add_child(body)

# ---------- 发现区域触发 ----------
func _build_trigger() -> void:
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(COLS * PITCH, 20.0, ROWS * PITCH)
	cs.shape = sh
	cs.position = Vector3(ORIGIN_X + (COLS - 1) * PITCH * 0.5, 8.0, ORIGIN_Z + (ROWS - 1) * PITCH * 0.5)
	area.add_child(cs)
	area.body_entered.connect(_on_enter)
	_root.add_child(area)

func _on_enter(body: Node) -> void:
	if _entered:
		return
	if not body.is_in_group("player"):
		return
	_entered = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_banner"):
		hud.show_banner("发现新区域", "东岸新城 · VICE BEACH")

# ---------- 街灯 ----------
func _streetlight(x: float, z: float) -> void:
	if _rng.randf() >= 0.5:
		return
	var ground := _gy(x, z)
	var lamp := Node3D.new()
	lamp.position = Vector3(x + 3.0, ground, z + 3.0)
	_decor.add_child(lamp)
	var pole_mat := _mat(Color(0.15, 0.15, 0.18), 0.6)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = 7.0
	pole.mesh = cm
	pole.material_override = pole_mat
	pole.position.y = 3.5
	lamp.add_child(pole)
	var bulb_mat := _mat(Color(1.0, 0.9, 0.6), 0.3)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_energy_multiplier = 1.6
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	bulb.mesh = sm
	bulb.material_override = bulb_mat
	bulb.position.y = 7.0
	lamp.add_child(bulb)

# ---------- 建筑实例化 + 自动盒碰撞 ----------
func _place_building(path: String, x: float, z: float, yaw: float, scale: float) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var gy := _gy(x, z)
	var holder := Node3D.new()
	holder.position = Vector3(x, gy, z)
	holder.rotation.y = yaw
	_buildings.add_child(holder)
	var mdl: Node3D = ps.instantiate()
	mdl.scale = Vector3.ONE * scale
	holder.add_child(mdl)
	# 合并 AABB（holder 局部空间；_gather 递归会乘入 mdl 的 scale）
	var boxes: Array[AABB] = []
	_gather(mdl, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var merged: AABB = boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = merged.size
	cs.shape = sh
	cs.position = merged.get_center()
	body.add_child(cs)
	holder.add_child(body)

## 无碰撞纯装饰（树/花坛/车道）
func _place_decor(path: String, x: float, z: float, yaw: float, scale: float) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var gy := _gy(x, z)
	var holder := Node3D.new()
	holder.position = Vector3(x, gy, z)
	holder.rotation.y = yaw
	var mdl: Node3D = ps.instantiate()
	mdl.scale = Vector3.ONE * scale
	holder.add_child(mdl)
	_decor.add_child(holder)

func _gather(n: Node, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(xf * (n as MeshInstance3D).mesh.get_aabb())
	for ch in n.get_children():
		_gather(ch, xf, out)
