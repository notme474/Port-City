extends Node3D
## 帮派分子：据点战敌人。程序化黑衣胶囊 + 红眼，零资产依赖。
## HitArea 在 layer 2（武器射线 mask=3 命中），武器沿父链调 bullet_hit()。
## 自驱 AI：玩家进仇恨圈追击，近身挥击；玩家逃离则回据点出生点。

signal died(node: Node3D)

const MAX_HP := 100.0
const SPEED := 4.6
const AGGRO_R := 48.0
const LEASH_R := 85.0
const ATTACK_R := 3.0
const ATTACK_CD := 0.85
const DMG := 7.0

var hp := MAX_HP
var ground_y := 0.0
var home := Vector3.ZERO
var alive := true

var player: Node
var _mat: StandardMaterial3D
var _flash := 0.0
var _cd := 0.0

func setup(p: Node, gy: float, h: Vector3) -> void:
	player = p
	ground_y = gy
	home = h

func _ready() -> void:
	name = "帮派分子"
	_build()
	set_physics_process(true)

func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.08, 0.11)
	_mat.roughness = 0.7
	var body_mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.55
	cap.height = 1.9
	body_mi.mesh = cap
	body_mi.material_override = _mat
	body_mi.position.y = 1.05
	add_child(body_mi)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.25, 0.12, 0.12)
	hm.emission_enabled = true
	hm.emission = Color(0.6, 0.05, 0.05)
	hm.emission_energy_multiplier = 0.8
	head.mesh = sph
	head.material_override = hm
	head.position.y = 2.25
	add_child(head)
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
	if _mat:
		_mat.albedo_color = Color(0.8, 0.15, 0.15) if _flash > 0.0 else Color(0.08, 0.08, 0.11)
	_cd = maxf(0.0, _cd - delta)
	var pp: Vector3 = player.global_position
	var d := Vector3(pp.x - global_position.x, 0.0, pp.z - global_position.z).length()
	var target := pp
	var chasing := d < AGGRO_R and d < LEASH_R
	if not chasing:
		target = home
		if global_position.distance_to(home) <= 3.0:
			return
	var move_dir: Vector3 = target - global_position
	move_dir.y = 0.0
	if move_dir.length() > 0.5:
		var spd := SPEED if chasing else SPEED * 0.7
		global_position += move_dir.normalized() * spd * delta
		var yaw: float = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))
	global_position.y = ground_y
	if chasing and d < ATTACK_R and _cd <= 0.0:
		_cd = ATTACK_CD
		if player.has_method("take_damage"):
			player.take_damage(DMG)
