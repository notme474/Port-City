extends Node3D

signal view_mode_changed(first_person: bool)

@export_group("Properties")
@export var target: Node

@export_group("Zoom")
@export var zoom_minimum = 16
@export var zoom_maximum = 4
@export var zoom_speed = 10

@export_group("Rotation")
@export var rotation_speed = 120

# 视野档位（行业常用值）：第一人称 85° 更广、第三人称 70° 更稳
const FOV_FIRST := 85.0
const FOV_FIRST_ADS := 72.0
const FOV_THIRD := 70.0
const FOV_CHASE := 72.0
const FP_EYE_H := 1.45           # 第一人称眼高（米）
const TP_ANCHOR := 1.70          # 第三人称相机锚点：从脚部上移到头/肩（不再对着脚）
const TP_SHOULDER := 0.45        # 第三人称肩侧偏移（越肩视角）

var camera_rotation: Vector3
var zoom = 10
var _mouse_vel := Vector2.ZERO   ## 鼠标速度平滑缓冲（防晕3D）

var _was_captured := false        ## 上一帧鼠标是否处于锁定状态
var _capture_at_ms := -100000     ## 最近一次进入锁定的时刻（毫秒）
var _last_mouse_ms := -100000     ## 最近一次真实鼠标转镜头的时刻（驾驶时自由看用）

# ---------- 驾驶追尾相机 ----------
var chase: Node3D = null          ## 所驾驶的车辆；非 null 时追尾模式
var _reverse_t := 0.0             ## 倒车持续时间（满 0.4s 镜头转去车头前方）
var _reversing := false
var _bob_t := 0.0                 ## 行走镜头抖动的相位（随移动速度推进）

# ---------- 视角模式 ----------
var first_person := false         ## true=第一人称（隐藏身体，枪挂到相机）
var _fp_aiming := false

# ---------- 后坐力 / 震屏 ----------
var _recoil := Vector2.ZERO       # (偏航, 俯仰) 弧度，自动衰减回零，不污染基础视角
var _shake := 0.0                 # 震屏幅度（米），自动衰减
var _was_floor := true

@onready var camera = $Camera

func _ready():
	camera_rotation = rotation_degrees
	camera.fov = FOV_THIRD
	_reg_action("toggle_view", KEY_T)
	_load_view_pref()

func _reg_action(act: String, key: Key) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act)
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(act, ev)

func _notification(what: int) -> void:
	# 窗口失焦（Alt-Tab/点到别的窗口）时释放全部相机动作
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for action in ["camera_left", "camera_right", "camera_up", "camera_down", "zoom_in", "zoom_out"]:
			Input.action_release(action)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 鼠标转镜头放在 _input（GUI 过滤之前），确保任何时候真实鼠标移动都能收到。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 0.01:
		var pm := _pause_menu()
		if pm and pm.has_method("note_mouse_active"):
			pm.note_mouse_active()
		_track_capture()
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		# 刚进入锁定的 120ms 内忽略所有移动
		if Time.get_ticks_msec() - _capture_at_ms < 120:
			return
		var kbm: bool = pm == null or pm.is_kbm()
		if kbm:
			# 水平/垂直灵敏度可分别调节
			var sx: float = pm.get_sensitivity_x() if pm else 0.25
			var sy: float = pm.get_sensitivity_y() if pm else sx
			var rel: Vector2 = event.relative.limit_length(80.0)
			# 一丢丢输入平滑（0.82）：削掉鼠标毛刺防晕3D，幅度小到不可察觉
			_mouse_vel = _mouse_vel.lerp(rel, 0.82)
			camera_rotation.y -= _mouse_vel.x * sx
			camera_rotation.x = clampf(camera_rotation.x - _mouse_vel.y * sy, -80, 45)
			_last_mouse_ms = Time.get_ticks_msec()
	elif event is InputEventMouseButton and event.pressed:
		var pm2 := _pause_menu()
		if pm2 == null or pm2.is_kbm():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _track_capture() -> void:
	var cap: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if cap and not _was_captured:
		_capture_at_ms = Time.get_ticks_msec()
	_was_captured = cap

func _pause_menu() -> Node:
	return get_tree().current_scene.get_node_or_null("PauseMenu")

# ---------- 视角切换 ----------
func toggle_view() -> void:
	if chase != null:
		return   # 驾驶中强制追尾，不允许第一人称
	_set_first_person(not first_person)

func _set_body_visible(v: bool) -> void:
	if target and "model" in target:
		var m: Node = target.get("model")
		if m:
			m.visible = v

func _set_first_person(v: bool) -> void:
	if first_person == v:
		return
	first_person = v
	# 切换瞬间清掉后坐/震幅，避免残留偏移
	_recoil = Vector2.ZERO
	_shake = 0.0
	_set_body_visible(not v)
	view_mode_changed.emit(v)
	# 偏好持久化到设置文件
	var pm := _pause_menu()
	if pm and pm.has_method("set_view_pref"):
		pm.set_view_pref(v)

func _load_view_pref() -> void:
	# PauseMenu 可能尚未就绪，延迟几帧尝试读取
	for i in 5:
		var pm := _pause_menu()
		if pm and pm.has_method("get_view_pref"):
			first_person = bool(pm.get_view_pref())
			_set_body_visible(not first_person)
			view_mode_changed.emit(first_person)
			return
		await get_tree().process_frame

# ---------- 外部接口：后坐力 / 震屏（武器、受伤调用） ----------
func add_recoil(pitch_deg: float, yaw_deg := 0.0) -> void:
	_recoil.x = clampf(_recoil.x + deg_to_rad(yaw_deg), -0.25, 0.25)
	_recoil.y = clampf(_recoil.y + deg_to_rad(pitch_deg), -0.05, 0.45)

func add_shake(amount: float) -> void:
	# 震屏上限压低（0.35→0.20）：防晕3D，冲击感仍保留但不晃头
	_shake = clampf(maxf(_shake, amount), 0.0, 0.20)

# ---------- 驾驶模式切换（vehicle_manager 调用） ----------
func start_chase(car: Node3D) -> void:
	chase = car
	if first_person:
		_set_first_person(false)
	if car and car.view_target:
		target = car.view_target
	camera_rotation.y = _car_heading_deg(car)
	camera_rotation.x = clampf(camera_rotation.x, -20.0, 25.0)
	_reverse_t = 0.0
	_reversing = false

func end_chase() -> void:
	chase = null
	_reversing = false

func _car_heading_deg(car: Node3D) -> float:
	return wrapf(car.global_rotation_degrees.y + 180.0, -180.0, 180.0)

func _physics_process(delta):
	_track_capture()

	# T 键切换第一/第三人称
	if Input.is_action_just_pressed("toggle_view"):
		toggle_view()

	# 后坐力自动回位（约 0.3s），震屏快速衰减
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	_shake = maxf(0.0, _shake - delta * 1.4)

	# 跟随：灵敏度菜单里的"镜头跟随"0=零延迟硬跟，越大越柔和
	var pm_s := _pause_menu()
	var follow: float = pm_s.get_follow() if pm_s and pm_s.has_method("get_follow") else 0.0
	var pos_rate := lerpf(32.0, 7.0, clampf(follow, 0.0, 1.0))

	if chase != null and is_instance_valid(chase):
		_update_chase(delta)
	else:
		var target_pos: Vector3 = target.global_position
		# 第三人称锚点上移到头/肩（VC 式越肩视角），第一人称用眼部
		if not first_person and chase == null:
			target_pos += Vector3.UP * TP_ANCHOR
		# 第一人称始终硬跟（延迟会直接导致晕动）
		if first_person or pos_rate >= 28.0:
			self.global_position = target_pos
		else:
			self.global_position = self.global_position.lerp(target_pos, clampf(delta * pos_rate, 0.0, 1.0))
	# 基础朝向硬跟输入，叠加可恢复的后坐角
	rotation_degrees = camera_rotation + Vector3(rad_to_deg(_recoil.y), rad_to_deg(_recoil.x), 0.0)

	# 瞄准 / 变焦（aim 动作由武器系统运行时注册，首帧可能尚不存在）
	var aim_held: bool = InputMap.has_action("aim") and Input.is_action_pressed("aim")
	_fp_aiming = first_person and chase == null and aim_held
	var zoom_target: float
	var fov_target: float
	if chase != null:
		zoom_target = 12.5
		var boosting: bool = bool(chase.get("nitro_active"))
		fov_target = FOV_CHASE * (1.12 if boosting else 1.0)
	elif first_person:
		zoom_target = 0.0
		fov_target = FOV_FIRST_ADS if _fp_aiming else FOV_FIRST
	else:
		zoom_target = 4.0 if aim_held else 10.0
		fov_target = FOV_THIRD
	zoom = lerpf(zoom, zoom_target, delta * 6)
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 10.0, 0.0, 1.0))

	# 行走镜头抖动：厘米级（上下 2.8cm / 左右 1.8cm），驾驶/第一人称静止时不抖
	var bob := Vector3.ZERO
	if chase == null and target != null and not first_person:
		var vel: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
		var hs: float = Vector2(vel.x, vel.z).length()
		_bob_t += delta * hs * 1.05
		var amp: float = clampf(hs / 7.0, 0.0, 1.0)
		bob = Vector3(cos(_bob_t) * 0.018, sin(_bob_t * 2.0) * 0.028, 0.0) * amp

	# 落地轻微震一下（落地瞬间垂直速度大）
	if chase == null and target != null:
		var on_floor: bool = bool(target.is_on_floor()) if target is CharacterBody3D else true
		if on_floor and not _was_floor:
			add_shake(0.05)
		_was_floor = on_floor

	# 相机位置
	var shake_off := Vector3.ZERO
	if _shake > 0.001:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	if first_person:
		# 眼睛位置；贴脸 z=0，随瞄准微微前移
		camera.position = Vector3(bob.x * 0.5, FP_EYE_H, -0.08) + shake_off
	else:
		var cam_z: float = zoom
		var cam_y: float = 2.6 if chase != null else 0.0
		# 越肩视角：第三人称步行时相机偏向右肩（角色在画面偏左）
		var shoulder: float = TP_SHOULDER if chase == null else 0.0
		# 防穿模：从锚点（已上移至头/肩）向期望机位做射线，撞到世界(layer 1)就把相机拉到撞点前
		var eye := Vector3(shoulder, cam_y, 0)
		var desired := Vector3(shoulder + bob.x, cam_y, cam_z) + shake_off
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			to_global(eye), to_global(desired), 1)
		q.collide_with_areas = false
		if target is CollisionObject3D:
			q.exclude = [(target as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var pulled: Vector3 = to_local(hit.position)
			# 留出 0.35m 净空，避免相机贴墙
			pulled.z -= 0.35
			pulled.x = shoulder + bob.x
			pulled.y += shake_off.y
			camera.position = pulled
		else:
			camera.position = desired

	handle_input(delta)

## 追尾相机：硬锁定车后方；动鼠标 0.9s 内不回正；持续倒车转到车头前方
func _update_chase(delta: float) -> void:
	var car: Node3D = chase
	var aim_pos: Vector3 = car.view_target.global_position if car.view_target else car.global_position
	self.global_position = aim_pos + Vector3.UP * 1.1

	var speed: float = float(car.get("_speed"))
	if speed < -0.6:
		_reverse_t += delta
	else:
		_reverse_t = maxf(0.0, _reverse_t - delta * 1.5)
	if _reverse_t > 0.4:
		_reversing = true
	elif speed > 0.6:
		_reversing = false

	var free_look: bool = Time.get_ticks_msec() - _last_mouse_ms < 900
	if not free_look:
		camera_rotation.y = _car_heading_deg(car) + (180.0 if _reversing else 0.0)

# Handle input

func handle_input(delta):
	var pm := _pause_menu()
	var kbm: bool = pm == null or pm.is_kbm()

	var input := Vector3.ZERO
	if kbm:
		input.y = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		input.x = float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	else:
		input.y = Input.get_axis("camera_left", "camera_right")
		input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clamp(camera_rotation.x, -80, 45)

	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clamp(zoom, zoom_maximum, zoom_minimum)
