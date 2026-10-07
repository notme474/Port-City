extends Node3D
## 主城便民车：在城市周边道路上放若干可驾驶车辆，靠近按 F 上车、再按 F 下车。
## 复用 Starter Kit 的 CarVehicle + vehicle_manager，车顶有青色悬浮光柱方便找车。

const VEH_SCENE := "res://objects/vehicle.tscn"
const MARK_COL := Color(0.35, 0.95, 1.0)

# 车型 GLB / 出生点（y 给高一点，车辆靠重力自然落地）
const CARS := [
	["res://GLB format/轿车.glb", Vector3(138, 6.4, -48), 0.0],
	["res://GLB format/出租车.glb", Vector3(102, 6.4, -64), 180.0],
	["res://GLB format/轿车_运动.glb", Vector3(62, 6.4, -8), 90.0],
	["res://GLB format/SUV.glb", Vector3(-232, 6.4, 126), -90.0],
	["res://GLB format/赛车_未来.glb", Vector3(296, 6.4, 216), 0.0],
	["res://GLB format/卡丁车_oobi.glb", Vector3(152, 6.4, 34), 180.0],
]

var player: Node3D
var _manager: Node3D
var _root: Node3D
var _hint: Label
var _driving := false

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	player = get_tree().get_first_node_in_group("player")
	var view: Node3D = get_tree().current_scene.get_node_or_null("View")
	# 车辆管理器（与高空汽车岛同款）
	_manager = Node3D.new()
	_manager.name = "CityCarManager"
	_manager.set_script(load("res://scripts/vehicle_manager.gd"))
	add_child(_manager)
	_root = Node3D.new()
	_root.name = "车辆"
	_manager.add_child(_root)
	for spec in CARS:
		_spawn_car(str(spec[0]), spec[1], float(spec[2]))
	# 显式注入引用，防止管理器自动查找路径找不到
	_manager.set("player", player)
	_manager.set("view", view)
	_manager.set("vehicles_root", _root)
	_build_hint()

func _spawn_car(glb_path: String, pos: Vector3, yaw_deg: float) -> void:
	var sc: PackedScene = load(VEH_SCENE)
	if sc == null:
		return
	var car: CharacterBody3D = sc.instantiate()
	var glb: PackedScene = load(glb_path)
	car.set("model_scene", glb)
	car.position = pos
	car.rotation_degrees.y = yaw_deg
	_root.add_child(car)
	_make_marker(car)

## 车顶悬浮光柱 + 旋转钻石，远处就能看到车
func _make_marker(car: Node3D) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = MARK_COL
	m.emission_enabled = true
	m.emission = MARK_COL
	m.emission_energy_multiplier = 3.0
	# 光柱
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, 0.12)
	beam_mat.emission_enabled = true
	beam_mat.emission = MARK_COL
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.35
	bm.height = 9.0
	beam.mesh = bm
	beam.material_override = beam_mat
	beam.position.y = 6.0
	car.add_child(beam)
	# 浮动钻石（方块旋转 45° 当菱形）
	var gem := MeshInstance3D.new()
	var om := BoxMesh.new()
	om.size = Vector3(0.6, 0.6, 0.6)
	gem.mesh = om
	gem.material_override = m
	gem.name = "CarGem"
	gem.position.y = 3.2
	gem.rotation_degrees = Vector3(45, 45, 0)
	car.add_child(gem)

func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position = Vector2(-200, 110)
	_hint.size = Vector2(400, 40)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", MARK_COL)
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_hint)

func _process(_delta: float) -> void:
	if _manager == null or player == null or not is_instance_valid(player):
		return
	# 钻石自旋/上下浮动
	var t: float = Time.get_ticks_msec() / 1000.0
	for car in _root.get_children():
		var gem: Node3D = car.get_node_or_null("CarGem")
		if gem:
			gem.rotation.y = t * 2.4
			gem.position.y = 3.2 + sin(t * 2.6 + car.global_position.x) * 0.22
	# 驾驶中提示下车，附近有车提示上车
	var driving: bool = _manager.get("_driving") != null
	var near: bool = _manager.get("_nearest") != null
	if driving:
		_hint.text = "驾驶中：W/S 油门刹车    A/D 转向    空格刹车    F 下车"
		_hint.visible = true
	else:
		_hint.text = "按 F 上车"
		_hint.visible = near
