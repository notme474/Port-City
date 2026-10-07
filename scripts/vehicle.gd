extends CharacterBody3D
class_name CarVehicle

## 可驾驶汽车：CharacterBody3D + 车身碰撞盒 + 重力 + 车轮滚动/前轮转向
## 车体模型（GLB）在运行时实例化，碰撞盒按模型包围盒自动生成

@export var model_scene: PackedScene           ## 车体模型（GLB，车头朝 +Z）
@export var model_scale := 1.0                 ## 模型缩放
@export var model_yaw_deg := 180.0             ## 朝向修正：GLB 车头朝 +Z，物理前向为 -Z

@export_group("行驶参数")
@export var max_speed := 22.0                  ## 前进最高速度 m/s
@export var reverse_speed := 8.0               ## 倒车最高速度 m/s
@export var acceleration := 14.0               ## 加速度
@export var brake_decel := 26.0                ## 松开油门后的减速
@export var steer_max_deg := 26.0              ## 前轮最大转角
@export var wheel_base := 2.6                  ## 轴距（转向模型用）
@export var steer_speed := 3.0                 ## 前轮转向响应速度
@export var gravity := 26.0                    ## 重力加速度

@export_group("四轮下压与姿态")
@export var downforce := 7.0                   ## 四轮贴地下压力总和（m/s²，四点平均分配）
@export var airborne_pull := 46.0              ## 悬空轮的强下拉（让离地车轮尽快回地）
@export var pitch_stability := 9.0             ## 前后（俯仰）回正强度 —— 前后重一点
@export var roll_stability := 2.4              ## 左右（侧倾）回正强度 —— 左右轻一点
@export var max_yaw_rate := 1.9                ## 最大转向角速度 rad/s（防止小车轴距过短原地狂甩）

var driver: CharacterBody3D = null             ## 当前驾驶员（为空即无人驾驶）
var view_target: Node3D = null                 ## 摄像机跟随点

var _speed := 0.0
var _roll := 0.0
var _steer := 0.0
var _front_wheels: Array[Node3D] = []
var _rear_wheels: Array[Node3D] = []
var _wheel_radius := 0.0
var _wheel_points: Array[Node3D] = []          ## 四个重力点（左前/右前/左后/右后）
var _spawn_transform: Transform3D


func _ready() -> void:
	_spawn_transform = global_transform
	_build()


## 组装车体：模型 + 碰撞盒 + 车轮枢轴 + 摄像机跟随点
func _build() -> void:
	# Model 节点本身不旋转不缩放，只做位移修正；偏航/缩放施加在内部的 GLB 实例上，
	# 这样包围盒与位移都统一在车身坐标系里计算，不受 180° 偏航影响
	var model_root := Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	if model_scene != null:
		var inner := model_scene.instantiate() as Node3D
		inner.rotation_degrees.y = model_yaw_deg
		inner.scale = Vector3.ONE * model_scale
		model_root.add_child(inner)

	var height := 1.2
	var box := _model_aabb(model_root)

	if box.size.length() > 0.01:
		# 模型在 X/Z 上居中、底面落到车身原点，使碰撞盒底边正好贴在路面上
		model_root.position = -Vector3(
			box.position.x + box.size.x * 0.5,
			box.position.y,
			box.position.z + box.size.z * 0.5)
		height = box.size.y

		var shape := BoxShape3D.new()
		shape.size = Vector3(
			maxf(box.size.x, 0.4) * 0.92,
			maxf(box.size.y, 0.4) * 0.9,
			maxf(box.size.z, 0.4) * 0.96)
		var col := CollisionShape3D.new()
		col.name = "Body"
		col.shape = shape
		col.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
		add_child(col)

		_setup_wheels(model_root)

	view_target = Node3D.new()
	view_target.name = "ViewTarget"
	view_target.position = Vector3(0.0, maxf(height * 0.7, 0.9), 0.0)
	add_child(view_target)


## 计算模型在车身坐标系下的整体包围盒
func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var to_root := root.global_transform.affine_inverse()
	for mi in _find_meshes(root):
		var a: AABB = (to_root * mi.global_transform) * mi.get_aabb()
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


## 把每个车轮包一层枢轴：枢轴 X 轴滚动、前轮枢轴 Y 轴转向
func _setup_wheels(root: Node3D) -> void:
	var wheels: Array[Node3D] = []
	_find_wheels(root, wheels)
	var front_z := 0.0
	var rear_z := 0.0
	var front_n := 0
	var rear_n := 0
	for w in wheels:
		var wheel_name := String(w.name)
		var is_front := wheel_name.begins_with("wheel-front-")
		if not is_front and not wheel_name.begins_with("wheel-back-"):
			continue
		if w is MeshInstance3D:
			_wheel_radius = maxf(_wheel_radius, w.get_aabb().size.y * 0.5)
		var parent := w.get_parent()
		var pivot := Node3D.new()
		pivot.name = "Pivot_" + wheel_name
		parent.add_child(pivot)
		pivot.transform = w.transform
		w.reparent(pivot, false)
		w.transform = Transform3D.IDENTITY
		var local_z := root.to_local(pivot.global_position).z
		if is_front:
			_front_wheels.append(pivot)
			front_z += local_z
			front_n += 1
		else:
			_rear_wheels.append(pivot)
			rear_z += local_z
			rear_n += 1
	if front_n > 0 and rear_n > 0:
		var span := absf(front_z / front_n - rear_z / rear_n) * model_scale
		if span > 0.5:
			wheel_base = span

	# 四个重力点：前轴、后轴各自的左右轮（枢轴即轮心）
	_wheel_points.clear()
	for w in _front_wheels:
		_wheel_points.append(w)
	for w in _rear_wheels:
		_wheel_points.append(w)


func _find_wheels(root: Node3D, found: Array[Node3D]) -> void:
	for child in root.get_children():
		if child is Node3D:
			if String(child.name).begins_with("wheel"):
				found.append(child)
			_find_wheels(child, found)


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_input := 0.0
	var braking := false

	if driver != null:
		# 油门：键盘 W/S + 手柄 RT/LT（扳机）。左摇杆只管转向、不供油
		var kb := 0.0
		if Input.is_physical_key_pressed(KEY_W):
			kb += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			kb -= 1.0
		throttle = clampf(kb + _trigger_axis(JOY_AXIS_TRIGGER_RIGHT) - _trigger_axis(JOY_AXIS_TRIGGER_LEFT), -1.0, 1.0)
		steer_input = Input.get_axis("move_right", "move_left")
		braking = Input.is_action_pressed("jump")

	if throttle > 0.01:
		_speed = move_toward(_speed, max_speed, acceleration * delta)
	elif throttle < -0.01:
		_speed = move_toward(_speed, -reverse_speed, acceleration * delta)
	else:
		_speed = move_toward(_speed, 0.0, brake_decel * delta)

	if braking:
		_speed = move_toward(_speed, 0.0, brake_decel * delta)

	# 转向：前轮角度随车速收敛，车速越高转角越小
	var speed_ratio := clampf(absf(_speed) / max_speed, 0.0, 1.0)
	var target_steer := steer_input * deg_to_rad(steer_max_deg) * clampf(absf(_speed) / 4.0, 0.0, 1.0)
	_steer = lerpf(_steer, target_steer, clampf(delta * steer_speed, 0.0, 1.0))

	if absf(_speed) > 0.05:
		var limited := _steer * (1.0 - 0.55 * speed_ratio)
		# 自行车模型求角速度并封顶，轴距过短的小车（如卡丁车）也不会原地狂甩
		var yaw_rate := clampf(_speed / wheel_base * tan(limited), -max_yaw_rate, max_yaw_rate)
		rotate_y(yaw_rate * delta)

	# 姿态回正（前后俯仰强、左右侧倾轻）
	_stabilize_pose(delta)

	# 四个重力点：逐轮向下检测，接地轮平均分摊贴地下压力，悬空轮强下拉
	var extra_down := _wheel_downforce()

	# 位移只取车身前向的水平分量，避免倾斜时把速度带进 Y
	var fwd := -global_transform.basis.z
	var forward := Vector3(fwd.x, 0.0, fwd.z)
	if forward.length() > 0.001:
		forward = forward.normalized()
	if is_on_floor():
		velocity.y = -1.0 - downforce
	else:
		velocity.y -= (gravity + extra_down) * delta
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed
	move_and_slide()

	_animate_wheels(delta)

	# 掉出世界则回到出生位置
	if global_position.y < -30.0:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO
		_speed = 0.0


## 读取手柄扳机（LT/RT），带死区并兼容 0..1 与 -1..1 两种报告方式
func _trigger_axis(axis: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, axis)
	if v < 0.0:
		v = (v + 1.0) * 0.5
	return clampf((v - 0.2) / 0.8, 0.0, 1.0)


## 姿态回正：把车体的俯仰/侧倾往水平方向掰。前后（俯仰）回正强、左右（侧倾）轻；
## 四轮离地（空中）时减弱但仍回正，避免倒扣落地
func _stabilize_pose(delta: float) -> void:
	var b := global_transform.basis
	# 本地 +Z 轴（车尾）的抬升量 -> 俯仰角；本地 +X 轴（车右）的抬升量 -> 侧倾角
	var pitch := asin(clampf(b.z.y, -1.0, 1.0))
	var roll := atan2(b.x.y, b.y.y)
	var air_factor := 1.0 if is_on_floor() else 0.35
	var kp := clampf(pitch_stability * air_factor * delta, 0.0, 1.0)
	var kr := clampf(roll_stability * air_factor * delta, 0.0, 1.0)
	# 绕本地 X 轴消俯仰、绕本地 Z 轴消侧倾
	rotate(Vector3.RIGHT, pitch * kp)
	rotate(Vector3(0.0, 0.0, 1.0), -roll * kr)


## 四个重力点：每个轮心向下投射，接地的轮平均分摊贴地下压力，悬空的轮强下拉，
## 返回额外下压加速度（m/s²）
func _wheel_downforce() -> float:
	if _wheel_points.is_empty():
		return 0.0
	var space := get_world_3d().direct_space_state
	var extra := 0.0
	var ray_len := _wheel_radius + 0.5
	for w in _wheel_points:
		var center: Vector3 = w.global_position
		var q := PhysicsRayQueryParameters3D.create(
			center + Vector3.UP * 0.25, center - Vector3.UP * ray_len)
		q.exclude = [get_rid()]
		q.collision_mask = collision_mask
		if space.intersect_ray(q).is_empty():
			# 该轮悬空：平均分摊的强下拉
			extra += airborne_pull / float(_wheel_points.size())
	return extra


func _animate_wheels(delta: float) -> void:
	if _wheel_radius <= 0.0:
		return
	_roll = fmod(_roll + _speed * delta / _wheel_radius, TAU)
	for w in _front_wheels:
		w.rotation = Vector3(_roll, _steer, 0.0)
	for w in _rear_wheels:
		w.rotation = Vector3(_roll, 0.0, 0.0)


## 无人驾驶时清零，避免被推走后一直滑动
func stop() -> void:
	_speed = 0.0
	velocity = Vector3.ZERO
