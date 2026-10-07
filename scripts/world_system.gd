extends Node3D
## 世界系统：海面 + 恐龙岛 + 大码头（含控制小屋）+ 可驾驶小船
## 运行时生成，挂到 main.tscn 根节点。模型在 res://models/

const M := "res://models/"
const WATER_Y := -1.2          ## 海面高度（低于岛面 y=0）
const DOCK_POS := Vector3(760, WATER_Y, 420)   ## 大码头（东南海面）
const DINO_ISLAND := Vector3(-1050, WATER_Y, -700)  ## 恐龙岛（西南外海）
const CITY_CENTER := Vector2(60, -20)

## 额外的岛：{名字, 位置, 半径, 主题}
const EXTRA_ISLANDS := [
	{"name": "绿岛", "pos": Vector3(1150, WATER_Y, -300), "r": 110.0, "kind": "forest"},
	{"name": "沙洲岛", "pos": Vector3(-500, WATER_Y, 950), "r": 90.0, "kind": "sand"},
	{"name": "灯塔岩岛", "pos": Vector3(900, WATER_Y, 950), "r": 70.0, "kind": "rock"},
]

func _ready() -> void:
	_build_ocean()
	_build_dock()
	_build_dino_island()
	_build_arch_bridge()
	_build_extra_islands()
	_spawn_boats()

func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

# ---------- 海面：一个蓝色大方块 ----------
func _build_ocean() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "海洋"
	var bm := BoxMesh.new()
	bm.size = Vector3(4000, 1.0, 4000)
	mi.mesh = bm
	var mat := _mat(Color(0.16, 0.42, 0.62), 0.5)
	mat.metallic = 0.3
	mat.roughness = 0.25
	mi.material_override = mat
	mi.position = Vector3(60, WATER_Y - 0.5, -20)
	add_child(mi)

# ---------- 大码头 + 控制小屋 ----------
func _build_dock() -> void:
	var dock_root := Node3D.new()
	dock_root.name = "大码头"
	dock_root.position = DOCK_POS
	add_child(dock_root)

	# 可视木甲板（62×42，顶面局部 y=1.0 → 世界 -0.2，与碰撞齐平）
	var deck_mi := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(62, 0.8, 42)
	deck_mi.mesh = dm
	deck_mi.material_override = _mat(Color(0.45, 0.30, 0.16), 0.9)
	deck_mi.position = Vector3(0, 0.6, 0)
	dock_root.add_child(deck_mi)

	# 码头小模型（×6 约 8m 宽木结构），贴甲板放在西南角作码头设施
	var dock_scene: PackedScene = load(M + "dock.glb")
	if dock_scene:
		var dock: Node3D = dock_scene.instantiate()
		ModelUtil.snap_to_ground(dock, 6.0, 1.0)
		dock.position.x = -25.0
		dock.position.z = -11.0
		dock_root.add_child(dock)

	# 码头控制小屋（×10 约 8.3m），贴甲板顶面 y=1.0
	var hut_scene: PackedScene = load("res://Kenney 城市套件·郊区/Models/GLB format/building-type-a.glb")
	if hut_scene:
		var hut: Node3D = hut_scene.instantiate()
		ModelUtil.snap_to_ground(hut, 10.0, 1.0)
		hut.position = Vector3(-14, hut.position.y, -10)
		dock_root.add_child(hut)
		_add_box_col(dock_root, Vector3(-14, 5.17, -10), Vector3(8, 8.34, 8))

	# 码头平台碰撞（大平面，可站可停船，顶面局部 y=1.0）
	_add_box_col(dock_root, Vector3(0, -0.5, 0), Vector3(60, 3, 40))

func _add_box_col(parent: Node, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var sh := BoxShape3D.new()
	sh.size = size
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)

# ---------- 恐龙岛：小岛 + 多只恐龙 ----------
func _build_dino_island() -> void:
	var island := Node3D.new()
	island.name = "恐龙岛"
	island.position = DINO_ISLAND
	add_child(island)

	# 岛体（圆柱，绿顶棕边）。岛节点在水面 y=-1.2，局部 y=8.0 对齐世界 y=6.8（拱形桥终点）
	var cyl := CylinderMesh.new()
	cyl.top_radius = 150.0
	cyl.bottom_radius = 170.0
	cyl.height = 14.0
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = cyl
	body_mesh.material_override = _mat(Color(0.42, 0.30, 0.18))  # 泥土
	body_mesh.position.y = 1.0
	island.add_child(body_mesh)
	var grass := CylinderMesh.new()
	grass.top_radius = 148.0
	grass.bottom_radius = 148.0
	grass.height = 0.6
	var gm := MeshInstance3D.new()
	gm.mesh = grass
	gm.material_override = _mat(Color(0.32, 0.55, 0.24))  # 草地
	gm.position.y = 7.7
	island.add_child(gm)
	# 岛面碰撞（顶面局部 y=8.0 → 世界 6.8，与桥面齐平）
	_add_box_col(island, Vector3(0, 1, 0), Vector3(290, 14, 290))

	# 恐龙：岛上散布 5 只，每只带血条、可被车撞
	var dino_scene: PackedScene = load(M + "dino.glb")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if dino_scene:
		for i in range(5):
			var a := rng.randf() * TAU
			var r := rng.randf_range(30.0, 120.0)
			var dpos := Vector3(cos(a) * r, 8.0, sin(a) * r)
			# dino.glb 蒙皮实际高 45.7 单位（网格 AABB 0.31 是绑定姿态，不可直接用），
			# ×0.12~0.15 → 约 5.5~6.9m 的霸王龙
			var sc := rng.randf_range(0.12, 0.15)
			_spawn_dino(island, dino_scene, dpos, rng.randf() * TAU, sc)

## 生成一只带血条/HP/可被撞的恐龙
func _spawn_dino(parent: Node, scene: PackedScene, pos: Vector3, yaw: float, sc: float) -> void:
	var dino := Node3D.new()
	dino.name = "恐龙"
	dino.position = pos
	dino.rotation.y = yaw
	dino.set_script(load("res://scripts/dino.gd"))
	dino.set("max_hp", 100.0)
	parent.add_child(dino)
	var mdl: Node3D = scene.instantiate()
	ModelUtil.snap_to_ground(mdl, sc)
	dino.add_child(mdl)
	# 碰撞（被撞检测由 dino.gd 的 Area 处理）
	_add_box_col(dino, Vector3(0, 4, 0), Vector3(8, 8, 14))

## 新增多个小岛
func _build_extra_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for isl in EXTRA_ISLANDS:
		var node := Node3D.new()
		node.name = isl.name
		node.position = isl.pos
		add_child(node)
		var r: float = isl.r
		# 岛体（局部顶面 y=8.0 → 世界 6.8，与恐龙岛/桥面一致）
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r * 1.12
		cyl.height = 13.0
		var bm := MeshInstance3D.new()
		bm.mesh = cyl
		bm.material_override = _mat(_island_ground_color(isl.kind))
		bm.position.y = 0.5
		node.add_child(bm)
		# 顶部
		var top := CylinderMesh.new()
		top.top_radius = r * 0.98
		top.bottom_radius = r * 0.98
		top.height = 0.6
		var tm := MeshInstance3D.new()
		tm.mesh = top
		tm.material_override = _mat(_island_top_color(isl.kind))
		tm.position.y = 7.7
		node.add_child(tm)
		# 岛面碰撞（顶面 y=8.0）
		_add_box_col(node, Vector3(0, 1, 0), Vector3(r * 1.9, 14, r * 1.9))
		# 按主题点缀
		_decorate_island(node, isl.kind, r, rng)

# ---------- 拱形桥：主岛 ↔ 恐龙岛 ----------
func _build_arch_bridge() -> void:
	var A := Vector3(-500, 5.95, -340)    # 主岛西南端（主城地面 y=5.95）
	var B := Vector3(-900, 6.8, -610)     # 恐龙岛东北端（岛面世界 y=6.8）
	var ARCH_H := 22.0                    # 拱顶抬高
	var N := 36                           # 桥面分段数
	var W := 14.0                         # 桥面宽（双向）
	var DECK_H := 0.9                     # 桥面厚

	var bridge := Node3D.new()
	bridge.name = "拱形桥"
	add_child(bridge)

	var pts := []
	for i in range(N + 1):
		var t := float(i) / N
		var base := A.lerp(B, t)
		var arc := ARCH_H * 4.0 * t * (1.0 - t)
		pts.append(Vector3(base.x, base.y + arc, base.z))

	# 桥面段
	for i in range(N):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var mid := (p1 + p2) * 0.5
		var d := p2 - p1
		var len := d.length()
		# 方向角
		var yaw := atan2(d.x, d.z)
		var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
		var bm := BoxMesh.new()
		bm.size = Vector3(W, DECK_H, len)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _mat(Color(0.5, 0.48, 0.45), 0.7)
		mi.position = mid
		mi.rotation = Vector3(pitch, yaw, 0)
		bridge.add_child(mi)
		# 桥面碰撞
		var body := StaticBody3D.new()
		body.position = mid
		body.rotation = Vector3(pitch, yaw, 0)
		bridge.add_child(body)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(W, DECK_H, len)
		cs.shape = box
		body.add_child(cs)

	# 两侧栏杆
	var rail_h := 1.4
	var rail_col := Color(0.75, 0.72, 0.68)
	for side in [-1.0, 1.0]:
		for i in range(N + 1):
			var p: Vector3 = pts[i]
			var d: Vector3 = (pts[mini(i + 1, N)] - pts[maxi(i - 1, 0)]).normalized()
			var right: Vector3 = Vector3(-d.z, 0, d.x).normalized() * side * (W * 0.5)
			# 竖杆
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.18
			pm.bottom_radius = 0.18
			pm.height = rail_h
			post.mesh = pm
			post.material_override = _mat(rail_col, 0.6)
			post.position = p + right + Vector3(0, rail_h * 0.5 + DECK_H * 0.5, 0)
			bridge.add_child(post)
		# 横杆（分段）
		for i in range(N):
			var p1: Vector3 = pts[i]
			var p2: Vector3 = pts[i + 1]
			var d := (p2 - p1)
			var len := d.length()
			var mid := (p1 + p2) * 0.5
			var yaw := atan2(d.x, d.z)
			var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
			var right: Vector3 = Vector3(-d.z, 0, d.x).normalized() * side * (W * 0.5)
			var top_off := Vector3(0, rail_h + DECK_H * 0.5, 0)
			var rail := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.22, 0.22, len)
			rail.mesh = rm
			rail.material_override = _mat(rail_col, 0.6)
			rail.position = mid + right + top_off
			rail.rotation = Vector3(pitch, yaw, 0)
			bridge.add_child(rail)

	# 拱肋装饰：桥面下方一条曲线拱（用扁 Box 沿桥方向）
	for i in range(N):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var mid := (p1 + p2) * 0.5
		var d := p2 - p1
		var len := d.length()
		var yaw := atan2(d.x, d.z)
		var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
		var rib := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(W * 0.5, 1.2, len)
		rib.mesh = rm
		rib.material_override = _mat(Color(0.4, 0.38, 0.36), 0.7)
		rib.position = mid + Vector3(0, -1.4, 0)
		rib.rotation = Vector3(pitch, yaw, 0)
		bridge.add_child(rib)
	print("[Bridge] arch bridge built A=", A, " B=", B)

func _island_ground_color(kind: String) -> Color:
	match kind:
		"sand": return Color(0.82, 0.72, 0.5)
		"rock": return Color(0.4, 0.4, 0.42)
	return Color(0.42, 0.30, 0.18)

func _island_top_color(kind: String) -> Color:
	match kind:
		"sand": return Color(0.92, 0.84, 0.62)
		"rock": return Color(0.5, 0.5, 0.52)
	return Color(0.32, 0.55, 0.24)

func _decorate_island(node: Node3D, kind: String, r: float, rng: RandomNumberGenerator) -> void:
	match kind:
		"forest":
			var tree_sc: PackedScene = load("res://Kenney 城市套件·郊区/Models/GLB format/tree-large.glb")
			if tree_sc:
				for i in range(12):
					var a := rng.randf() * TAU
					var rr := rng.randf_range(15, r * 0.8)
					var t: Node3D = tree_sc.instantiate()
					t.position = Vector3(cos(a) * rr, 0, sin(a) * rr)
					ModelUtil.snap_to_ground(t, 10, 8.0)  # 岛顶面局部 y=8.0
					t.rotation.y = rng.randf() * TAU
					node.add_child(t)
		"rock":
			# 灯塔
			var tower_sc: PackedScene = load("res://GLB format/塔_完整_小型.glb")
			if tower_sc:
				var tw: Node3D = tower_sc.instantiate()
				ModelUtil.snap_to_ground(tw, 10, 8.0)  # 岛顶面局部 y=8.0
				node.add_child(tw)
			# 灯塔灯（塔基 8.0、塔高约 68m，灯放在顶部灯室）
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.9, 0.6)
			l.light_energy = 4.0
			l.omni_range = 80
			l.position = Vector3(0, 74, 0)
			node.add_child(l)

# ---------- 小船：码头边 + 城市海岸各一艘 ----------
func _spawn_boats() -> void:
	var boat_script := load("res://scripts/boat.gd")
	var boat_model: PackedScene = load("res://GLB format/船_小型.glb")
	for pos in [DOCK_POS + Vector3(40, 0, 10), Vector3(500, WATER_Y, 480)]:
		var b := CharacterBody3D.new()
		b.set_script(boat_script)
		b.set("model_scene", boat_model)
		b.set("model_scale", 8.0)
		b.set("water_y", WATER_Y)
		b.position = Vector3(pos.x, WATER_Y, pos.z)
		add_child(b)
