extends Node3D

@export_group("Properties")
@export var target: Node

@export_group("Zoom")
@export var zoom_minimum = 16
@export var zoom_maximum = 4
@export var zoom_speed = 10

@export_group("Rotation")
@export var rotation_speed = 120

var camera_rotation:Vector3
var zoom = 10

var _was_captured := false        ## 上一帧鼠标是否处于锁定状态
var _capture_at_ms := -100000     ## 最近一次进入锁定的时刻（毫秒）
var _last_mouse_ms := -100000     ## 最近一次真实鼠标转镜头的时刻（驾驶时自由看用）

# ---------- 驾驶追尾相机 ----------
var chase: Node3D = null          ## 所驾驶的车辆；非 null 时追尾模式
var _reverse_t := 0.0             ## 倒车持续时间（满 0.4s 镜头转去车头前方）
var _reversing := false
var _bob_t := 0.0                 ## 行走镜头抖动的相位（随移动速度推进）

@onready var camera = $Camera

func _ready():
	camera_rotation = rotation_degrees # Initial rotation

func _notification(what: int) -> void:
	# 窗口失焦（Alt-Tab/点到别的窗口）时释放全部相机动作，
	# 否则丢失的 key-up / 摇杆回中事件会让镜头一直朝一个方向狂转
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for action in ["camera_left", "camera_right", "camera_up", "camera_down", "zoom_in", "zoom_out"]:
			Input.action_release(action)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 鼠标转镜头放在 _input（GUI 过滤之前），确保任何时候真实鼠标移动都能收到。
## 暂停时本节点（PAUSABLE）不接收输入回调，不会和菜单冲突。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 0.01:
		var pm := _pause_menu()
		# 鼠标一旦真实移动就视为键鼠输入（手柄漂移/坏存档也能立刻恢复转镜头）
		if pm and pm.has_method("note_mouse_active"):
			pm.note_mouse_active()
		_track_capture()
		# 只有鼠标被锁定时才转镜头：光标自由滑动（暂停/失焦/手柄模式）绝不转视角，
		# 否则光标一次跨屏移动就是几百度的甩镜
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		# 刚进入锁定的 120ms 内忽略所有移动：锁定瞬间系统会产生一次
		# "从旧位置跳到屏幕中心"的大位移事件，不忽略就会疯甩一下
		if Time.get_ticks_msec() - _capture_at_ms < 120:
			return
		var kbm: bool = pm == null or pm.is_kbm()
		if kbm:
			var s: float = pm.get_sensitivity() if pm else 0.25
			# 单次位移限幅：过滤异常大的一次性事件（快速甩动略受限，可接受）
			var rel: Vector2 = event.relative.limit_length(80.0)
			camera_rotation.y -= rel.x * s
			camera_rotation.x = clampf(camera_rotation.x - rel.y * s, -80, 45)
			_last_mouse_ms = Time.get_ticks_msec()
	elif event is InputEventMouseButton and event.pressed:
		# 点回窗口时确保鼠标锁定
		var pm2 := _pause_menu()
		if pm2 == null or pm2.is_kbm():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 检测"刚进入鼠标锁定"的时刻，用于忽略锁定瞬间的一次性跳变事件
func _track_capture() -> void:
	var cap: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if cap and not _was_captured:
		_capture_at_ms = Time.get_ticks_msec()
	_was_captured = cap

func _pause_menu() -> Node:
	return get_tree().current_scene.get_node_or_null("PauseMenu")

# ---------- 驾驶模式切换（vehicle_manager 调用） ----------
func start_chase(car: Node3D) -> void:
	chase = car
	if car and car.view_target:
		target = car.view_target
	# 镜头先放到车后方
	camera_rotation.y = _car_heading_deg(car)
	camera_rotation.x = clampf(camera_rotation.x, -20.0, 25.0)
	_reverse_t = 0.0
	_reversing = false

func end_chase() -> void:
	chase = null
	_reversing = false

func _car_heading_deg(car: Node3D) -> float:
	# 车辆物理前向为 -Z（yaw=0 时朝 -Z 开），所以车头朝向 = yaw + 180
	return wrapf(car.global_rotation_degrees.y + 180.0, -180.0, 180.0)

func _physics_process(delta):
	_track_capture()

	if chase != null and is_instance_valid(chase):
		_update_chase(delta)
	else:
		# 位置硬跟目标：零弹性，人在哪镜头就在哪
		self.global_position = target.global_position
	# 朝向硬跟：镜头角度即所见角度，没有任何平滑/惯性
	rotation_degrees = camera_rotation

	# 按住右键瞄准时镜头拉近（驾驶中不瞄准，镜头保持追尾距离）
	var aiming: bool = chase == null and InputMap.has_action("aim") and Input.is_action_pressed("aim")
	var zoom_target := 4.0 if aiming else (12.5 if chase != null else 10.0)
	zoom = lerpf(zoom, zoom_target, delta * 6)

	# 行走镜头抖动：步伐带动极轻微上下颠 + 左右晃，随速度增强、停下即消失
	# 幅度刻意压到厘米级（上下 2.8cm / 左右 1.8cm），只给"在走"的体感，不晃眼
	var bob := Vector3.ZERO
	if chase == null and target != null:
		var vel: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
		var hs: float = Vector2(vel.x, vel.z).length()
		_bob_t += delta * hs * 1.05
		var amp: float = clampf(hs / 7.0, 0.0, 1.0)
		bob = Vector3(cos(_bob_t) * 0.018, sin(_bob_t * 2.0) * 0.028, 0.0) * amp
	var cam_y: float = 2.6 if chase != null else 0.0
	camera.position = Vector3(bob.x, cam_y + bob.y, zoom)

	handle_input(delta)

## 追尾相机：硬锁定车后方，零惯性；刚动鼠标 0.9s 内不回正，保留自由环顾；
## 持续倒车时镜头转到车头前方，方便倒车看路
func _update_chase(delta: float) -> void:
	var car: Node3D = chase
	var aim_pos: Vector3 = car.view_target.global_position if car.view_target else car.global_position
	# 跟随点抬高 1.1m 越过车顶看路，硬跟不拖影
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

	# 玩家正在动鼠标环顾 → 不抢镜头；松开后镜头立刻掰回车后方
	var free_look: bool = Time.get_ticks_msec() - _last_mouse_ms < 900
	if not free_look:
		camera_rotation.y = _car_heading_deg(car) + (180.0 if _reversing else 0.0)

# Handle input

func handle_input(delta):
	var pm := _pause_menu()
	var kbm: bool = pm == null or pm.is_kbm()

	# Rotation
	var input := Vector3.ZERO
	if kbm:
		# 键鼠模式：方向键仍可转镜头，但绝不读游戏摇杆轴——
		# 噪声手柄的摇杆漂移连在 camera_left/right 动作上，
		# 以前它能在键鼠模式下让镜头永远自己转（疯转停不下来的根因）
		input.y = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		input.x = float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	else:
		input.y = Input.get_axis("camera_left", "camera_right")
		input.x = Input.get_axis("camera_up", "camera_down")

	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clamp(camera_rotation.x, -80, 45)

	# Zooming（键鼠滚轮走 zoom 动作，手柄走摇杆键）
	zoom += Input.get_axis("zoom_in", "zoom_out") * zoom_speed * delta
	zoom = clamp(zoom, zoom_maximum, zoom_minimum)
