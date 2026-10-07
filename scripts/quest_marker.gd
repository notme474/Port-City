extends Node3D
## GTA 罪恶都市式任务光圈：地面发光黄圈 + 半透明光柱 + 旋转能量环。
## 玩家走入光圈即触发任务（替代原来的靠近按 F）。

signal triggered

const RING_IN := 1.30
const RING_OUT := 2.05

var _color: Color = Color(1.0, 0.85, 0.25)
var _title := "任务"
var _t := 0.0
var _used := false
var _spin: Node3D
var _spin2: Node3D
var _beam_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D

## 父节点需在世界原点附近（任务系统都在主场景根下，位置即世界坐标）
func setup(pos: Vector3, color: Color = Color(1.0, 0.85, 0.25), title: String = "任务") -> void:
	_color = color
	_title = title
	position = pos
	_build()

func _build() -> void:
	# 触发区：薄圆柱，mask=1 检测玩家
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RING_OUT
	cyl.height = 2.6
	cs.shape = cyl
	cs.position.y = 1.3
	area.add_child(cs)
	area.body_entered.connect(_on_body_entered)
	add_child(area)

	# 地面发光环（Torus 默认轴为 Z，绕 X 转 90° 平躺）
	_ring_mat = _neon_mat(_color, 3.2)
	var ground := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_IN
	tm.outer_radius = RING_OUT
	ground.mesh = tm
	ground.rotation_degrees = Vector3(90, 0, 0)
	ground.position.y = 0.06
	ground.material_override = _ring_mat
	# 圈底暗色圆盘，让黄圈在亮色路面上也醒目
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.12, 0.08, 0.0, 0.55)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = RING_OUT
	dm.bottom_radius = RING_OUT
	dm.height = 0.04
	disc.mesh = dm
	disc.position.y = 0.03
	disc.material_override = disc_mat
	add_child(disc)
	add_child(ground)

	# 半透明光柱
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.16)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = _color
	_beam_mat.emission_energy_multiplier = 1.2
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = RING_OUT
	bm.bottom_radius = RING_OUT
	bm.height = 6.0
	beam.mesh = bm
	beam.position.y = 3.0
	beam.material_override = _beam_mat
	add_child(beam)

	# 旋转能量环 ×2（上下浮动 + 绕 Y 自转）
	_spin = _make_spin(0.62, 0.80)
	_spin2 = _make_spin(0.34, 0.48)
	add_child(_spin)
	add_child(_spin2)

	# 接任务文字（Billboard）
	var lbl := Label3D.new()
	lbl.text = "★ " + _title + " ★"
	lbl.font_size = 96
	lbl.modulate = _color
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 16
	lbl.outline_modulate = Color(0.1, 0.05, 0.0)
	lbl.position.y = 6.6
	add_child(lbl)

func _make_spin(r_in: float, r_out: float) -> Node3D:
	var pivot := Node3D.new()
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	mi.mesh = tm
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.material_override = _neon_mat(_color, 3.2)
	pivot.add_child(mi)
	return pivot

func _neon_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.08, 0.06, 0.02)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _process(delta: float) -> void:
	_t += delta
	_spin.rotation.y += delta * 1.8
	_spin2.rotation.y -= delta * 2.6
	_spin.position.y = 0.9 + sin(_t * 2.2) * 0.35
	_spin2.position.y = 2.1 + cos(_t * 2.8) * 0.45
	# 光柱呼吸
	var a: float = 0.07 + (sin(_t * 3.0) * 0.5 + 0.5) * 0.08
	_beam_mat.albedo_color = Color(_color.r, _color.g, _color.b, a)
	_ring_mat.emission_energy_multiplier = 2.0 + sin(_t * 4.0) * 0.8

func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if body.is_in_group("player"):
		_used = true
		triggered.emit()
		queue_free()
