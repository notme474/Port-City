extends Node3D

## 医院：城市中心偏北 (40,60)，白色主楼 + 发光红十字 + 玻璃幕墙 + 门口救护车。
## 玩家死亡后在门前绿色复活点重生。所有建筑/车辆带 StaticBody 碰撞。

const HOSP_XZ := Vector2(40, 60)     # 射线实测 y=5.95 路面，城市中心、距出生点约 150m

var _root: Node3D
var _ground_y := 6.0
var respawn_point: Vector3

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_ground_y = _gy()
	_root = Node3D.new()
	_root.name = "医院"
	add_child(_root)
	_build_hospital()
	_build_ambulance()
	_build_respawn_pad()
	# 复活点：门前台阶下街面
	respawn_point = Vector3(HOSP_XZ.x, _ground_y + 1.0, HOSP_XZ.y + 10.0)
	# 小地图标记
	var mm := get_parent().get_node_or_null("Minimap")
	if mm and mm.has_method("add_marker"):
		mm.add_marker("hospital", Vector3(HOSP_XZ.x, _ground_y, HOSP_XZ.y), Color(1, 0.25, 0.35), "医院")

# ---------- 建筑 ----------
func _build_hospital() -> void:
	var p := Vector3(HOSP_XZ.x, _ground_y, HOSP_XZ.y)

	# 地基平台
	_box(_root, Vector3(16, 0.5, 15), p + Vector3(0, 0.25, 0), _mat(Color(0.78, 0.8, 0.84)), true)
	# 主楼（白色 14×9×12）
	_box(_root, Vector3(14, 9, 12), p + Vector3(0, 4.5, -0.5), _mat(Color(0.93, 0.95, 0.98)), true)
	# 顶部压顶（一圈出檐）
	_box(_root, Vector3(14.6, 0.5, 12.6), p + Vector3(0, 9.25, -0.5), _mat(Color(0.86, 0.89, 0.94)), true)
	# 屋顶设备间
	_box(_root, Vector3(4, 2, 3.5), p + Vector3(-4, 10.5, -2), _mat(Color(0.8, 0.83, 0.88)), false)

	# 正面玻璃幕墙：3 排 × 5 扇深蓝玻璃
	var glass := _glass_mat(Color(0.2, 0.45, 0.75))
	for row in 3:
		for col in 5:
			var wx := -5.0 + col * 2.5
			var wy := 3.6 + row * 2.1
			_box(_root, Vector3(1.8, 1.5, 0.12), p + Vector3(wx, wy, 5.62), glass, false)
	# 侧窗（东西两面各 2 排 4 扇）
	for side in [-1, 1]:
		for row in 2:
			for col in 4:
				var wz: float = -4.5 + col * 2.7
				var wy: float = 4.0 + row * 2.4
				var wpos := p + Vector3(side * 7.06, wy, wz)
				var wn := _box(_root, Vector3(0.12, 1.5, 1.9), wpos, glass, false)
				wn.rotation.y = 0.0

	# 入口大门（深色玻璃双开门）
	_box(_root, Vector3(3.6, 3.0, 0.2), p + Vector3(0, 1.5, 5.66), _glass_mat(Color(0.1, 0.25, 0.45)), false)
	# 门框
	_box(_root, Vector3(4.0, 0.25, 0.25), p + Vector3(0, 3.1, 5.7), _mat(Color(0.95, 0.95, 0.97)), false)
	# 台阶（两级）
	_box(_root, Vector3(6, 0.25, 1.2), p + Vector3(0, 0.62, 6.1), _mat(Color(0.82, 0.84, 0.88)), true)
	_box(_root, Vector3(7, 0.25, 1.6), p + Vector3(0, 0.37, 6.7), _mat(Color(0.78, 0.8, 0.84)), true)
	# 入口雨棚（白平板，前沿发红光勾边）
	_box(_root, Vector3(6, 0.25, 3.2), p + Vector3(0, 3.5, 7.0), _mat(Color(0.92, 0.94, 0.98)), true)
	_box(_root, Vector3(6.1, 0.12, 0.12), p + Vector3(0, 3.32, 8.6), _glow(Color(1, 0.2, 0.25)), false)

	# 正面门楣红十字（发光）
	_red_cross(_root, p + Vector3(0, 4.9, 5.72), 1.0, false)

	# 楼顶红十字塔：立柱 + 两组垂直十字片，四面可见
	var tower := Node3D.new()
	tower.position = p + Vector3(4.2, 0, -3.5)
	_root.add_child(tower)
	_box(tower, Vector3(0.5, 4.0, 0.5), Vector3(0, 11.5, 0), _mat(Color(0.9, 0.92, 0.96)), false)
	_red_cross(tower, Vector3(0, 14.2, 0), 1.6, true)
	var cross2 := Node3D.new()
	cross2.rotation.y = PI / 2.0
	cross2.position = Vector3(0, 14.2, 0)
	tower.add_child(cross2)
	_red_cross(cross2, Vector3.ZERO, 1.6, true)

	# 门牌：医院 HOSPITAL（双面 Label3D）
	var lbl := Label3D.new()
	lbl.text = "医院\nHOSPITAL"
	lbl.font_size = 96
	lbl.pixel_size = 0.008
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0.6, 0.05, 0.1)
	lbl.modulate = Color(1, 0.95, 0.95)
	lbl.position = p + Vector3(-5.2, 5.6, 5.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.no_depth_test = false
	_root.add_child(lbl)

	# 门口两侧夜灯（昼夜系统接管：白天灭晚上亮）
	for sx in [-2.6, 2.6]:
		var lamp := OmniLight3D.new()
		lamp.name = "hospital_lamp"
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.light_energy = 0.0
		lamp.set_meta("night_energy", 2.2)
		lamp.omni_range = 12.0
		lamp.position = p + Vector3(sx, 3.2, 7.4)
		_root.add_child(lamp)
		# 灯柱
		_box(_root, Vector3(0.22, 3.2, 0.22), p + Vector3(sx, 1.6, 7.4), _mat(Color(0.9, 0.92, 0.95)), false)
		_box(_root, Vector3(0.5, 0.18, 0.5), p + Vector3(sx, 3.25, 7.4), _glow(Color(1, 0.9, 0.65)), false)
	# 楼顶十字投光（夜间红光映楼）
	var top_lamp := OmniLight3D.new()
	top_lamp.name = "hospital_cross_lamp"
	top_lamp.light_color = Color(1, 0.2, 0.25)
	top_lamp.light_energy = 0.0
	top_lamp.set_meta("night_energy", 2.6)
	top_lamp.omni_range = 16.0
	top_lamp.position = p + Vector3(4.2, 14.5, -3.5)
	_root.add_child(top_lamp)

	# 门前装饰灌木（两盆）
	for sx in [-3.4, 3.4]:
		var bush := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.7
		cm.height = 1.1
		bush.mesh = cm
		bush.position = p + Vector3(sx, 0.8, 7.6)
		bush.material_override = _mat(Color(0.2, 0.55, 0.25))
		_root.add_child(bush)
		_box(_root, Vector3(1.0, 0.55, 1.0), p + Vector3(sx, 0.52, 7.6), _mat(Color(0.45, 0.35, 0.28)), false)

## 红十字（竖+横两片红色发光盒），sc 控制整体大小
func _red_cross(parent: Node3D, center: Vector3, sc: float, with_body: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.12, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.08, 0.12)
	mat.emission_energy_multiplier = 2.2
	_box(parent, Vector3(0.55 * sc, 1.9 * sc, 0.18), center, mat, false)
	_box(parent, Vector3(1.9 * sc, 0.55 * sc, 0.18), center, mat, false)
	if with_body:
		pass

# ---------- 救护车 ----------
func _build_ambulance() -> void:
	var pos := Vector3(HOSP_XZ.x - 5.2, _ground_y, HOSP_XZ.y + 8.8)
	var body := StaticBody3D.new()
	body.name = "医院救护车"
	body.position = pos
	_root.add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.2, 5.2)
	col.position = Vector3(0, 1.1, 0)
	col.shape = box
	body.add_child(col)
	# 模型
	var ps: PackedScene = load("res://GLB format/救护车.glb")
	if ps:
		var mdl: Node3D = ps.instantiate()
		ModelUtil.snap_to_ground(mdl, 1.0, 0.0)
		# GLB 朝 +Z，Godot 物理前向 -Z：转 180° 让车头朝外（+Z 街方向）
		mdl.rotation.y = PI
		# 原 GLB 是紫色玩具涂装，全车刷白强化"救护车"识别
		_paint_white(mdl)
		body.add_child(mdl)
	# 红色腰线（两侧）+ 车尾红十字 + 车顶十字 + 红色警示灯
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.1, 0.12)
	red.emission_enabled = true
	red.emission = Color(1, 0.06, 0.08)
	red.emission_energy_multiplier = 1.6
	_box(body, Vector3(0.08, 0.32, 3.2), Vector3(1.24, 1.25, 0), red, false)
	_box(body, Vector3(0.08, 0.32, 3.2), Vector3(-1.24, 1.25, 0), red, false)
	_box(body, Vector3(0.7, 0.16, 0.06), Vector3(0, 1.35, 2.62), red, false)
	_box(body, Vector3(0.16, 0.7, 0.06), Vector3(0, 1.35, 2.62), red, false)
	_box(body, Vector3(1.1, 0.08, 0.26), Vector3(0, 2.08, 0.2), red, false)
	_box(body, Vector3(0.26, 0.08, 1.1), Vector3(0, 2.08, 0.2), red, false)
	var beacon := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.12
	bcyl.bottom_radius = 0.12
	bcyl.height = 0.16
	beacon.mesh = bcyl
	beacon.position = Vector3(0, 2.22, -1.0)
	beacon.material_override = red
	body.add_child(beacon)

## 递归把 GLB 所有网格刷成白色（统一救护车车漆）
func _paint_white(n: Node) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.96, 0.97, 1.0)
	m.roughness = 0.6
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_paint_white(c)

# ---------- 复活点 ----------
func _build_respawn_pad() -> void:
	var pad := Node3D.new()
	pad.position = Vector3(HOSP_XZ.x, _ground_y + 0.06, HOSP_XZ.y + 10.0)
	_root.add_child(pad)
	# 绿色半透明圆环地贴（复活区）
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.2, 1.0, 0.55, 0.18)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.emission_enabled = true
	disc_mat.emission = Color(0.2, 1, 0.55)
	disc_mat.emission_energy_multiplier = 0.6
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 2.2
	cyl.height = 0.06
	disc.mesh = cyl
	disc.material_override = disc_mat
	pad.add_child(disc)
	# 复活点微光
	var glow := OmniLight3D.new()
	glow.name = "respawn_glow"
	glow.light_color = Color(0.3, 1, 0.6)
	glow.light_energy = 0.9
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.2, 0)
	pad.add_child(glow)

# ---------- 工具 ----------
func _gy() -> float:
	var from := Vector3(HOSP_XZ.x, 25.0, HOSP_XZ.y)
	var to := Vector3(HOSP_XZ.x, -5.0, HOSP_XZ.y)
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		parent.add_child(sb)
		sb.position = pos
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
	return mi

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _glass_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = c * 0.35
	m.emission_energy_multiplier = 0.5
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.5
	return m

## 外部接口：死亡系统取复活点
func get_respawn() -> Vector3:
	return respawn_point
