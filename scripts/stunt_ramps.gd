extends Node3D
## 特技跳跃台：东岸新城 6 个混凝土斜坡（真实斜面碰撞，车/人可冲上起飞）。
## 追踪玩家（或驾驶车辆 view.chase）的腾空水平距离与滞空时间，落地按距离发奖金，
## 最佳成绩写入统计（best_jump_dist），超长滞空有额外奖励。

const RAMP_W := 5.0
const RAMP_L := 12.0
const RAMP_T := 1.0
const RAMP_ANGLE := 0.25
const MIN_DIST := 12.0
const LAND_RAY := 2.8

var player: Node
var view: Node3D
var stats: Node

# [x, z, rot.x, rot.z]：坡朝 +z/-z/+x/-x 方向起飞，落点为路口对面直路
const RAMPS := [
	[412, -200, 0.25, 0.0],
	[540, -176, -0.25, 0.0],
	[460, -124, 0.0, 0.25],
	[492, -60, 0.0, -0.25],
	[604, -188, 0.0, -0.25],
	[348, -60, 0.25, 0.0],
]

var _airborne := false
var _start_pos := Vector3.ZERO
var _start_ms := 0
var _ground_frames := 0
var _air_frames := 0
var _cooldown := 0.0

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	stats = get_parent().get_node_or_null("StatsSystem")
	view = get_parent().get_node_or_null("View")
	for r in RAMPS:
		_build_ramp(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

func _build_ramp(x: float, z: float, rx: float, rz: float) -> void:
	var gy := _gy(x, z)
	var rise := RAMP_L * sin(absf(rx + rz))
	var holder := Node3D.new()
	holder.position = Vector3(x, gy + rise * 0.5, z)
	holder.rotation = Vector3(rx, 0.0, rz)
	add_child(holder)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	holder.add_child(sb)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(RAMP_W, RAMP_T, RAMP_L)
	cs.shape = sh
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(RAMP_W, RAMP_T, RAMP_L)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.42, 0.46)
	mat.roughness = 0.9
	mi.material_override = mat
	sb.add_child(mi)
	# 起跳端橙白条纹警示条（贴高端）
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(RAMP_W + 0.2, 0.12, 1.4)
	tip.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.55, 0.1)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.4, 0.05)
	tmat.emission_energy_multiplier = 0.7
	tip.material_override = tmat
	# 高端在局部 +z / +x（旋转符号决定），统一放在局部 +z 半端，rx/rz 已表达朝向
	tip.position = Vector3(0, RAMP_T * 0.5 + 0.06, RAMP_L * 0.5 - 0.7)
	holder.add_child(tip)

func _process(delta: float) -> void:
	if player == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var node: Node = _target_node()
	if node == null:
		return
	var grounded := _is_grounded(node)
	if grounded:
		_ground_frames += 1
		_air_frames = 0
	else:
		_air_frames += 1
		_ground_frames = 0
	var p: Vector3 = node.global_position
	if not _airborne:
		# 连续 3 帧离地且速度够快才算起跳
		if _air_frames >= 3 and _cooldown <= 0.0 and _speed(node) > 8.0:
			_airborne = true
			_start_pos = p
			_start_ms = Time.get_ticks_msec()
	else:
		# 落地（连续 2 帧接地）
		if _ground_frames >= 2:
			_finish(p)

func _finish(p: Vector3) -> void:
	_airborne = false
	_cooldown = 2.0
	var dist := Vector2(p.x - _start_pos.x, p.z - _start_pos.z).length()
	var air_t := (Time.get_ticks_msec() - _start_ms) / 1000.0
	if dist < MIN_DIST:
		return
	var reward := clampi(int(dist * 40.0), 300, 2500)
	var extra := air_t >= 1.6
	if extra:
		reward += 500
	if player and "coins" in player:
		player.coins += reward
		player.coin_collected.emit(player.coins)
	if stats:
		stats.add_stat("best_jump_dist", dist)
	var col := Color(1.0, 0.7, 0.2) if not extra else Color(1.0, 0.45, 0.2)
	var sub := "+%d 金币   滞空 %.1f 秒" % [reward, air_t]
	if extra:
		sub = "滞空之王！  " + sub
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_banner"):
		hud._show_banner("特技跳跃  %.1f 米" % dist, col, 2.0)
		hud._show_banner(sub, col, 2.0)

## 当前追踪的物理主体：驾驶中是车，否则玩家
func _target_node() -> Node:
	if view and "chase" in view and view.chase != null:
		return view.chase
	return player

func _speed(node: Node) -> float:
	if node is CharacterBody3D:
		return (node as CharacterBody3D).velocity.length()
	if "velocity" in node:
		var v: Variant = node.get("velocity")
		if v is Vector3:
			return (v as Vector3).length()
	return 0.0

func _is_grounded(node: Node) -> bool:
	var sp := get_world_3d().direct_space_state
	var p: Vector3 = node.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.35, p + Vector3.DOWN * LAND_RAY, 1)
	q.exclude = [node.get_rid()]
	var hit: Dictionary = sp.intersect_ray(q)
	return not hit.is_empty()

func _gy(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -10.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else 5.95
