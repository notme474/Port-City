extends Node3D
## 帮派分子：据点战敌人。程序化胶囊体，零资产依赖。两种兵：
##  - 近战（黑衣）：冲进近身挥击
##  - 枪手（酒红）：保持 12~22m 距离风筝射击，有视线才开火，红色激光弹道
## HitArea 在 layer 2（武器射线 mask=3 命中），武器沿父链调 bullet_hit()。

signal died(node: Node3D)

const MAX_HP := 100.0
const MELEE_SPEED := 4.8
const RANGED_SPEED := 3.6
const AGGRO_R := 52.0
const LEASH_R := 90.0
const ATTACK_R := 3.0
const ATTACK_CD := 0.85
const DMG := 7.0
const SHOOT_CD := 1.7
const SHOOT_DMG := 6.0
const RANGED_MIN := 12.0
const RANGED_MAX := 22.0

var hp := MAX_HP
var ground_y := 0.0
var home := Vector3.ZERO
var alive := true
var ranged := false

var player: Node
var _mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _flash := 0.0
var _cd := 0.0
var _ram_cd := 0.0
const RAM_SPEED := 9.0
const RAM_DMG := 60.0
const RAM_R := 3.4
var _muzzle: Node3D
var _muzzle_light: OmniLight3D

func setup(p: Node, gy: float, h: Vector3, is_ranged: bool = false) -> void:
	player = p
	ground_y = gy
	home = h
	ranged = is_ranged

func _ready() -> void:
	name = "帮派枪手" if ranged else "帮派分子"
	_build()
	set_physics_process(true)

func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.36, 0.1, 0.15) if ranged else Color(0.08, 0.08, 0.11)
	_mat.roughness = 0.7
	var body_mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.55
	cap.height = 1.9
	body_mi.mesh = cap
	body_mi.material_override = _mat
	body_mi.position.y = 1.05
	add_child(body_mi)
	# 枪手加一条肩带（小黄块）便于辨认
	if ranged:
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.5, 0.9)
		band.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.9, 0.7, 0.2)
		bmat.emission_enabled = true
		bmat.emission = Color(0.8, 0.5, 0.1)
		bmat.emission_energy_multiplier = 0.6
		band.material_override = bmat
		band.position = Vector3(0.35, 1.35, 0.0)
		band.rotation.z = 0.5
		add_child(band)
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.25, 0.12, 0.12)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(0.9, 0.12, 0.1) if ranged else Color(0.6, 0.05, 0.05)
	_head_mat.emission_energy_multiplier = 1.2 if ranged else 0.8
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	head.mesh = sph
	head.material_override = _head_mat
	head.position.y = 2.25
	add_child(head)
	# 枪口发光点（枪手）
	if ranged:
		_muzzle = Node3D.new()
		_muzzle.position = Vector3(0.0, 1.6, -0.7)
		var ml := OmniLight3D.new()
		ml.light_color = Color(1, 0.25, 0.15)
		_muzzle_light = ml
		_muzzle.add_child(ml)
		add_child(_muzzle)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.2, 0.15)
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	lamp.position.y = 2.4
	add_child(lamp)
	var ha := Area3D.new()
	ha.name = "HitArea"
	ha.collision_layer = 2
	ha.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 2.4, 1.3)
	cs.shape = box
	cs.position.y = 1.2
	ha.add_child(cs)
	add_child(ha)
	# 头部命中区（节点名含 head，武器系统部位倍率自动 1.6x）
	var hh := Area3D.new()
	hh.name = "head_hit"
	hh.collision_layer = 2
	hh.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(0.72, 0.72, 0.72)
	hcs.shape = hbox
	hcs.position.y = 2.25
	hh.add_child(hcs)
	add_child(hh)

## 武器命中回调；返回 true 表示本次击杀（武器据此报 kill_confirmed）
func bullet_hit(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	_flash = 0.12
	if hp <= 0.0:
		alive = false
		died.emit(self)
		queue_free()
		return true
	return false

func _physics_process(delta: float) -> void:
	if not alive or player == null:
		return
	_flash = maxf(0.0, _flash - delta)
	if _muzzle_light and _muzzle_light.light_energy > 0.0:
		_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - delta * 40.0)
	if _mat:
		_mat.albedo_color = Color(0.85, 0.2, 0.2) if _flash > 0.0 else (
			Color(0.36, 0.1, 0.15) if ranged else Color(0.08, 0.08, 0.11))
	_cd = maxf(0.0, _cd - delta)
	_ram_cd = maxf(0.0, _ram_cd - delta)
	_check_car_ram()
	var pp: Vector3 = player.global_position
	var flat := Vector3(pp.x - global_position.x, 0.0, pp.z - global_position.z)
	var d := flat.length()
	if d >= LEASH_R or d >= AGGRO_R and not ranged:
		# 脱战回家
		if global_position.distance_to(home) > 3.0:
			_move_toward(home, MELEE_SPEED * 0.7, delta)
		return
	if ranged:
		_ranged_behavior(pp, d, delta)
	else:
		_melee_behavior(pp, d, delta)
	global_position.y = ground_y

## 驾驶车辆高速冲撞：直接受伤（敌人无物理碰撞体，用距离+车速判定）
func _check_car_ram() -> void:
	if _ram_cd > 0.0:
		return
	var holder := get_parent()
	if holder == null:
		return
	var view: Node = holder.get_node_or_null("../View")
	if view == null:
		return
	var car: Object = view.get("chase")
	if car == null or not (car is Node3D) or not is_instance_valid(car):
		return
	var c: Node3D = car as Node3D
	if Vector2(c.global_position.x - global_position.x,
			c.global_position.z - global_position.z).length() > RAM_R:
		return
	var spd := 0.0
	if car is CharacterBody3D:
		spd = (car as CharacterBody3D).velocity.length()
	if spd < RAM_SPEED:
		return
	_ram_cd = 0.7
	bullet_hit(RAM_DMG)
	if view.has_method("add_shake"):
		view.add_shake(0.35)

func _melee_behavior(pp: Vector3, d: float, delta: float) -> void:
	if d > 0.5:
		_move_toward(pp, MELEE_SPEED, delta)
	if d < ATTACK_R and _cd <= 0.0:
		_cd = ATTACK_CD
		if player.has_method("take_damage"):
			player.take_damage(DMG)
			_notify_hud()

func _ranged_behavior(pp: Vector3, d: float, delta: float) -> void:
	# 风筝：太远逼近，太近后撤，区间内站定瞄准
	var move_target := Vector3.ZERO
	var moving := false
	if d > RANGED_MAX:
		move_target = pp
		moving = true
	elif d < RANGED_MIN:
		# 朝远离玩家方向退
		move_target = global_position + Vector3(global_position.x - pp.x, 0,
			global_position.z - pp.z)
		moving = true
	if moving:
		_move_toward(move_target, RANGED_SPEED, delta)
	# 面向玩家
	var aim := Vector3(pp.x - global_position.x, 0, pp.z - global_position.z)
	if aim.length() > 0.1:
		var yaw: float = atan2(aim.x, aim.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))
	# 视线内才开火
	if _cd <= 0.0 and d > RANGED_MIN - 2.0 and d < AGGRO_R and _has_line_of_sight(pp):
		_cd = SHOOT_CD
		_shoot(pp)

func _move_toward(target: Vector3, spd: float, delta: float) -> void:
	var dirv: Vector3 = target - global_position
	dirv.y = 0.0
	if dirv.length() > 0.5:
		global_position += dirv.normalized() * spd * delta
		var yaw: float = atan2(dirv.x, dirv.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))

## 世界遮挡检测：射线被墙挡住则无视线；打到玩家/载具附近算可见
func _has_line_of_sight(pp: Vector3) -> bool:
	var sp := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.6
	var to := pp + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit: Dictionary = sp.intersect_ray(q)
	if hit.is_empty():
		return true   # 无碰撞=完全通透
	var hp2: Vector3 = hit.position
	return hp2.distance_to(to) < 2.6

func _shoot(pp: Vector3) -> void:
	var from := global_position + Vector3.UP * 1.6 - global_transform.basis.z * 0.8
	var to := pp + Vector3.UP * 1.1
	if _muzzle_light:
		_muzzle_light.light_energy = 4.0
	_tracer(from, to)
	# 命中：玩家不动时 9 成命中，跑动中 6 成
	var moving := _speed() > 6.0
	var hit_chance := 0.6 if moving else 0.9
	if randf() < hit_chance and player.has_method("take_damage"):
		player.take_damage(SHOOT_DMG)
		_notify_hud()

## 通知 HUD 在屏幕边缘显示指向本敌人的受击箭头
func _notify_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_damage_dir"):
		return
	var cam_yaw := 0.0
	var holder := get_parent()
	if holder:
		var view: Node = holder.get_node_or_null("../View")
		if view:
			cam_yaw = float((view.get("camera_rotation") as Vector3).y)
	var d: Vector3 = global_position - player.global_position
	d.y = 0.0
	if d.length() < 0.1:
		return
	d = d.normalized()
	var fwd := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	hud.show_damage_dir(Vector2(d.dot(right), d.dot(fwd)))

func _speed() -> float:
	if player is CharacterBody3D:
		return (player as CharacterBody3D).velocity.length()
	return 0.0

## 红色激光弹道，0.1 秒后消失
func _tracer(from: Vector3, to: Vector3) -> void:
	var holder := get_parent()
	if holder == null:
		return
	var line := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var lenv: float = from.distance_to(to)
	bm.size = Vector3(0.08, 0.08, maxf(0.1, lenv))
	line.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.25, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1, 0.2, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = mat
	holder.add_child(line)
	line.global_position = (from + to) * 0.5
	line.look_at(to, Vector3.UP)
	# BoxMesh 长轴是 y，look_at 让 -z 朝目标，需要把长轴转到 z
	line.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	var t := get_tree().create_timer(0.1)
	t.timeout.connect(line.queue_free)
