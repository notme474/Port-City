extends CharacterBody3D
class_name BoatVehicle

## 可驾驶小船：CharacterBody3D + 浮在水面（无重力下坠）+ 转向推进
## 复用汽车驾驶交互：W/S 前进后退、A/D 转向、E 上下船（由 vehicle_manager 调度）

@export var model_scene: PackedScene           ## 船体模型（GLB，船头朝 +Z）
@export var model_scale := 10.0                ## 城市套件统一放大 10 倍
@export var model_yaw_deg := 180.0             ## 朝向修正：模型船头朝 +Z，物理前向为 -Z

@export_group("航行参数")
@export var max_speed := 12.0                  ## 最高航速 m/s
@export var reverse_speed := 4.0               ## 倒退速度
@export var acceleration := 6.0                ## 推进加速度（水上惯性大，较小）
@export var decel := 3.0                       ## 松油门后的水流阻力减速
@export var turn_speed := 0.9                  ## 转向角速度 rad/s
@export var water_y := 0.0                     ## 水面高度（船体漂浮线）
@export var bob_amp := 0.12                    ## 上下浮动幅度
@export var bob_freq := 0.9                    ## 浮动频率

var driver: CharacterBody3D = null             ## 当前驾驶员
var view_target: Node3D = null                 ## 摄像机跟随点

var _speed := 0.0
var _bob_t := 0.0
var _spawn_transform: Transform3D


func _ready() -> void:
	_spawn_transform = global_transform
	_build()


## 组装船体：模型 + 碰撞盒 + 摄像机跟随点
func _build() -> void:
	var model_root := Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	if model_scene != null:
		var inner := model_scene.instantiate() as Node3D
		inner.rotation_degrees.y = model_yaw_deg
		inner.scale = Vector3.ONE * model_scale
		model_root.add_child(inner)

	var height := 2.0
	var box := _model_aabb(model_root)
	if box.size.length() > 0.01:
		# X/Z 居中、船底略低于漂浮线，使船身吃水一点
		model_root.position = -Vector3(
			box.position.x + box.size.x * 0.5,
			box.position.y + box.size.y * 0.18,
			box.position.z + box.size.z * 0.5)
		height = box.size.y

		var shape := BoxShape3D.new()
		shape.size = Vector3(
			maxf(box.size.x, 0.5) * 0.9,
			maxf(box.size.y, 0.5) * 0.85,
			maxf(box.size.z, 0.5) * 0.95)
		var col := CollisionShape3D.new()
		col.name = "Body"
		col.shape = shape
		col.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
		add_child(col)

	view_target = Node3D.new()
	view_target.name = "ViewTarget"
	view_target.position = Vector3(0.0, maxf(height * 0.7, 1.2), 0.0)
	add_child(view_target)


## 计算模型在船体坐标系下的整体包围盒
func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _find_meshes(root):
		var a: AABB = mi.transform * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _find_meshes(root: Node3D, found: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in root.get_children():
		if child is MeshInstance3D:
			found.append(child)
		if child is Node3D:
			_find_meshes(child, found)
	return found


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_input := 0.0

	if driver != null:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_input = Input.get_axis("move_right", "move_left")

	# 推进 / 倒退（水上惯性）
	if throttle > 0.01:
		_speed = move_toward(_speed, max_speed, acceleration * delta)
	elif throttle < -0.01:
		_speed = move_toward(_speed, -reverse_speed, acceleration * delta)
	else:
		_speed = move_toward(_speed, 0.0, decel * delta)

	# 转向：随航速线性，倒退时反向
	if absf(_speed) > 0.05:
		var dir := signf(_speed)
		rotate_y(steer_input * turn_speed * dir * clampf(absf(_speed) / max_speed, 0.2, 1.0) * delta)

	# 漂浮：锁定在水面并轻微上下浮动
	_bob_t += delta
	var bob := sin(_bob_t * bob_freq * TAU) * bob_amp
	var fwd := -global_transform.basis.z
	var forward := Vector3(fwd.x, 0.0, fwd.z)
	if forward.length() > 0.001:
		forward = forward.normalized()
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed
	velocity.y = 0.0
	move_and_slide()
	# 强制贴水面 + 浮动（不受重力）
	global_position.y = water_y + bob

	# 漂出世界边界则回到出生点
	if global_position.y < -30.0:
		global_transform = _spawn_transform
		_speed = 0.0


## 无人驾驶时清零，避免被推走后一直滑动
func stop() -> void:
	_speed = 0.0
	velocity = Vector3.ZERO
