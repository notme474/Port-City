extends Node3D

## 高架地铁（观赏元素）：22m 高八边形环线跨主城而过，玩家无法到达/乘坐。
## 混凝土箱梁 + 双轨 + 落地桥墩（柱脚射线贴地）；两列列车对向循环运行，
## 车身银灰、蓝色发光腰线、深色车窗。无碰撞体（高架玩家上不去）。

const TRACK_Y := 22.0            # 桥面高度（越过 y=18 的楼顶）
const SLAB_Y := 21.3             # 箱梁中心高度
const TRAIN_SPEED := 13.0

# 八边形环线角点（矩形 -90~210 / -120~100，角部切 24m），顺时针
const RING_XZ := [
	Vector2(186, -120), Vector2(210, -96), Vector2(210, 76), Vector2(186, 100),
	Vector2(-66, 100), Vector2(-90, 76), Vector2(-90, -96), Vector2(-66, -120),
]

var _path: Path3D
var _follow_a: PathFollow3D
var _follow_b: PathFollow3D

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_build_ring()
	_build_trains()

# ---------- 轨道 ----------
func _build_ring() -> void:
	_path = Path3D.new()
	_path.name = "地铁环线"
	var curve := Curve3D.new()
	for p in RING_XZ:
		curve.add_point(Vector3(p.x, TRACK_Y, p.y))
	curve.closed = true
	_path.curve = curve
	add_child(_path)

	var concrete := _mat(Color(0.55, 0.57, 0.6))
	var rail_mat := _mat(Color(0.22, 0.23, 0.27))
	for i in range(RING_XZ.size()):
		var a := Vector3(RING_XZ[i].x, TRACK_Y, RING_XZ[i].y)
		var b := Vector3(RING_XZ[(i + 1) % RING_XZ.size()].x, TRACK_Y, RING_XZ[(i + 1) % RING_XZ.size()].y)
		var seg := Node3D.new()
		var mid := (a + b) * 0.5
		seg.position = mid
		seg.rotation.y = atan2(-(b.z - a.z), b.x - a.x)
		_path.add_child(seg)
		var length := a.distance_to(b)
		# 箱梁（宽 4.5 厚 1.0）
		_mesh_box(seg, Vector3(length, 1.0, 4.5), Vector3(0, SLAB_Y - TRACK_Y, 0), concrete)
		# 双轨（深色细梁）
		_mesh_box(seg, Vector3(length, 0.18, 0.22), Vector3(0, SLAB_Y - TRACK_Y + 0.55, 0.9), rail_mat)
		_mesh_box(seg, Vector3(length, 0.18, 0.22), Vector3(0, SLAB_Y - TRACK_Y + 0.55, -0.9), rail_mat)
		# 两侧矮护沿
		_mesh_box(seg, Vector3(length, 0.7, 0.18), Vector3(0, SLAB_Y - TRACK_Y + 0.6, 2.15), concrete)
		_mesh_box(seg, Vector3(length, 0.7, 0.18), Vector3(0, SLAB_Y - TRACK_Y + 0.6, -2.15), concrete)
		# 桥墩（长段每 40m 一根，短切角段不放）
		if length > 45.0:
			var d := 22.0
			while d < length - 18.0:
				var t := d / length
				var wp: Vector3 = a.lerp(b, t)
				_build_pillar(wp)
				d += 40.0

func _build_pillar(p: Vector3) -> void:
	var gy := _ground_y(p)
	var top := SLAB_Y - 0.5
	var h := top - gy
	if h < 1.0:
		return
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.25
	cyl.height = h
	pillar.mesh = cyl
	pillar.position = Vector3(p.x, gy + h * 0.5, p.z)
	pillar.material_override = _mat(Color(0.6, 0.62, 0.65))
	_path.add_child(pillar)
	# 柱头托梁（横向扩大支撑箱梁）
	_mesh_box(_path, Vector3(3.6, 0.7, 5.2), Vector3(p.x, top - 0.2, p.z), _mat(Color(0.55, 0.57, 0.6)))

# ---------- 列车 ----------
func _build_trains() -> void:
	_follow_a = _new_follow(0.0)
	_follow_b = _new_follow(0.5)
	# A 正向 3 节，B 对向 3 节（起点错开半个环）
	for i in 3:
		_follow_a.add_child(_make_car(i, i == 0))
		_follow_b.add_child(_make_car(i, i == 2))

func _new_follow(ratio: float) -> PathFollow3D:
	var f := PathFollow3D.new()
	f.loop = true
	f.use_model_front = true          # -Z 朝行进方向
	f.rotation_mode = PathFollow3D.ROTATION_Y
	_path.add_child(f)                # 必须先入树，progress_ratio 才允许设置
	f.progress_ratio = ratio
	return f

func _make_car(idx: int, front: bool) -> Node3D:
	var car := Node3D.new()
	# 车厢沿 -Z 串联（车钩间距 13m）
	car.position = Vector3(0, TRACK_Y - 1.0, -13.0 * idx)
	# 银灰车身
	_mesh_box(car, Vector3(3.0, 2.7, 12.0), Vector3.ZERO, _mat(Color(0.72, 0.75, 0.8)))
	# 车顶深灰
	_mesh_box(car, Vector3(2.7, 0.25, 11.6), Vector3(0, 1.45, 0), _mat(Color(0.35, 0.37, 0.42)))
	# 深色车窗带（两侧）
	var glass := _train_glass()
	_mesh_box(car, Vector3(0.1, 0.95, 11.2), Vector3(1.52, 0.35, 0), glass)
	_mesh_box(car, Vector3(0.1, 0.95, 11.2), Vector3(-1.52, 0.35, 0), glass)
	# 蓝色发光腰线
	_mesh_box(car, Vector3(0.12, 0.22, 11.4), Vector3(1.56, -0.55, 0), _glow(Color(0.25, 0.7, 1.0)))
	_mesh_box(car, Vector3(0.12, 0.22, 11.4), Vector3(-1.56, -0.55, 0), _glow(Color(0.25, 0.7, 1.0)))
	# 车底暗带
	_mesh_box(car, Vector3(3.05, 0.7, 11.9), Vector3(0, -1.0, 0), _mat(Color(0.2, 0.22, 0.26)))
	if front:
		# 车头：端窗 + 红色标志灯
		_mesh_box(car, Vector3(2.2, 0.9, 0.1), Vector3(0, 0.45, -6.02), glass)
		_mesh_box(car, Vector3(0.5, 0.18, 0.12), Vector3(-0.7, -0.9, -6.06), _glow(Color(1, 0.15, 0.12)))
		_mesh_box(car, Vector3(0.5, 0.18, 0.12), Vector3(0.7, -0.9, -6.06), _glow(Color(1, 0.15, 0.12)))
	return car

func _process(delta: float) -> void:
	# _ready 延迟两帧才建好轨道，建完前 _path/curve 尚为空
	if _path == null or _path.curve == null or _follow_a == null:
		return
	var total: float = _path.curve.get_baked_length()
	_follow_a.progress += TRAIN_SPEED * delta
	_follow_b.progress -= TRAIN_SPEED * 0.82 * delta
	# loop=true 时 progress 自动回绕，保险夹一下
	if _follow_a.progress > total:
		_follow_a.progress -= total
	if _follow_b.progress < 0.0:
		_follow_b.progress += total

# ---------- 工具 ----------
func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _ground_y(p: Vector3) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, 28.0, p.z), Vector3(p.x, -5.0, p.z), 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.15
	m.roughness = 0.7
	return m

func _train_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.16, 0.26)
	m.metallic = 0.6
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = Color(0.55, 0.75, 1.0)
	m.emission_energy_multiplier = 0.55   # 夜间车厢亮窗感，白天不刺眼
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.25
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.2
	return m
