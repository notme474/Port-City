extends Node3D

## 路边装饰车：沿城市主次干道两侧停放的静态车辆（纯视觉 + 盒碰撞）。
## StaticBody3D 不吃物理帧；玩家与 NPC 都会被车身挡住，不会穿模。
## 位置贴道路控制点连线侧移 7m 的人行道/停车带。

const CARS := [
	# [GLB 路径, x, z, 朝向角(度, -Z 前向), 碰撞盒 宽/高/长]
	["res://GLB format/轿车.glb",        240, -24, -79.6, Vector3(2.1, 1.6, 4.5)],
	["res://GLB format/掀背车_运动.glb", 185, -25, -79.6, Vector3(2.1, 1.6, 4.5)],
	["res://GLB format/SUV_豪华.glb",    130, -22, -79.6, Vector3(2.2, 1.9, 5.0)],
	["res://GLB format/出租车.glb",      333, -130, -4.9, Vector3(2.1, 1.7, 4.6)],
	["res://GLB format/面包车.glb",      333, -240, -4.9, Vector3(2.2, 2.1, 5.2)],
	["res://GLB format/卡车_平板.glb",   336, -350, -4.9, Vector3(2.5, 2.8, 7.2)],
	["res://GLB format/轿车.glb",        -33, 120, -172.4, Vector3(2.1, 1.6, 4.5)],
	["res://GLB format/垃圾车.glb",      -55, 40, -172.4, Vector3(2.5, 2.9, 6.8)],
	["res://GLB format/货车.glb",        -60, -6, -92.4, Vector3(2.4, 2.5, 6.2)],
	["res://GLB format/消防车.glb",      -170, 0, -92.4, Vector3(2.5, 2.9, 6.8)],
	["res://GLB format/赛车_未来.glb",   112, -78, 90.0, Vector3(2.1, 1.2, 4.4)],
]

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var root := Node3D.new()
	root.name = "路边车辆"
	add_child(root)
	for spec in CARS:
		_spawn(root, str(spec[0]), float(spec[1]), float(spec[2]), deg_to_rad(float(spec[3])), spec[4])

func _spawn(root: Node3D, glb_path: String, x: float, z: float, yaw: float, box_size: Vector3) -> void:
	var gy := _ground_y(x, z)
	var body := StaticBody3D.new()
	body.name = "装饰车"
	body.position = Vector3(x, gy, z)
	body.rotation.y = yaw
	root.add_child(body)
	# 盒碰撞（车体），与朝向一致：box 长轴沿 body -Z
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	col.shape = bs
	col.position.y = box_size.y * 0.5
	body.add_child(col)
	# 视觉模型（GLB 朝 +Z，车盒朝 -Z：模型转 180° 对齐）
	var ps: PackedScene = load(glb_path)
	if ps == null:
		return
	var mdl: Node3D = ps.instantiate()
	mdl.rotation.y = PI
	body.add_child(mdl)
	ModelUtil.snap_to_ground(mdl, 1.0, 0.0)

func _ground_y(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 25.0, z), Vector3(x, -5.0, z), 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0
