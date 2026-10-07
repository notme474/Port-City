extends Node3D
## 交通局旋转车：固定环形路线巡逻，进入范围加速撞玩家，碰撞即死
## 通缉触发后随机刷 2~3 辆无差别撞击，30 秒或进安全区解除

const M := "res://models/"
const CITY_CENTER := Vector2(60, -20)
const PATROL_R := 380.0
const PATROL_SPEED := 14.0
const CHASE_SPEED := 26.0
const KILL_R := 3.0
const ALERT_R := 90.0

var player: CharacterBody3D
var cars: Array = []        # {node, angle, mode}
var wanted := false
var wanted_t := 0.0
var car_scene: PackedScene

func _ready() -> void:
	car_scene = load(M + "carspin.glb")
	call_deferred("_setup")

func _setup() -> void:
	player = get_tree().get_first_node_in_group("player")
	# 常驻 3 辆巡逻车
	for i in range(3):
		_spawn_patrol_car(TAU * i / 3.0)

## 造一辆旋转车：holder 负责移动（每帧 y 锁 0），模型作为子节点贴地，避免偏移被覆盖
func _make_car() -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var c: Node3D = car_scene.instantiate()
	ModelUtil.snap_to_ground(c, 8.0)
	holder.add_child(c)
	var area := Area3D.new()
	area.name = "HitArea"
	area.collision_mask = 1
	holder.add_child(area)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4, 3, 7)
	cs.shape = sh
	cs.position.y = 2
	area.add_child(cs)
	return holder

func _spawn_patrol_car(angle: float) -> void:
	if car_scene == null:
		return
	var holder := _make_car()
	var car := {"node": holder, "angle": angle, "mode": "patrol"}
	cars.append(car)
	var area: Area3D = holder.get_node("HitArea")
	area.body_entered.connect(_on_car_hit.bind(car))

func set_wanted(on: bool) -> void:
	if on and not wanted:
		wanted = true
		wanted_t = 30.0
		# 通缉：刷 2 辆追击车
		for i in range(2):
			_spawn_chaser()
	elif not on:
		wanted = false

func _spawn_chaser() -> void:
	if car_scene == null or player == null:
		return
	var holder := _make_car()
	holder.global_position = player.global_position + Vector3(randf_range(-80, 80), 0, randf_range(-80, 80))
	var car := {"node": holder, "angle": 0.0, "mode": "chase"}
	cars.append(car)
	var area: Area3D = holder.get_node("Area3D")
	area.body_entered.connect(_on_car_hit.bind(car))

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if wanted:
		wanted_t -= delta
		if wanted_t <= 0.0:
			set_wanted(false)
	for car in cars:
		if not is_instance_valid(car.node):
			continue
		if car.mode == "patrol":
			_patrol_move(car, delta)
		else:
			_chase_move(car, delta)

func _patrol_move(car: Dictionary, delta: float) -> void:
	car.angle += (PATROL_SPEED / PATROL_R) * delta
	var px: float = CITY_CENTER.x + cos(car.angle) * PATROL_R
	var pz: float = CITY_CENTER.y + sin(car.angle) * PATROL_R
	var target := Vector3(px, 5.95, pz)   # 主城地面 y=5.95
	car.node.global_position = target
	# 车头朝运动方向（切线）
	var tangent := Vector2(-sin(car.angle), cos(car.angle))
	car.node.rotation.y = atan2(tangent.x, tangent.y)
	# 旋转车身（"旋转车"特效：轻微自旋）
	car.node.rotate_y(2.0 * delta)
	# 玩家进入警戒圈 → 短暂加速撞向玩家
	var d: float = car.node.global_position.distance_to(player.global_position)
	if d < ALERT_R:
		var dir: Vector3 = (player.global_position - car.node.global_position)
		dir.y = 0
		car.node.global_position += dir.normalized() * CHASE_SPEED * 0.4 * delta

func _chase_move(car: Dictionary, delta: float) -> void:
	var dir: Vector3 = player.global_position - car.node.global_position
	dir.y = 0
	car.node.global_position += dir.normalized() * CHASE_SPEED * delta
	car.node.rotation.y = atan2(dir.x, dir.z)
	car.node.rotate_y(3.0 * delta)
	# 通缉结束则移除追击车
	if not wanted:
		car.node.queue_free()
		cars.erase(car)

func _on_car_hit(body: Node, car: Dictionary) -> void:
	if body == player and player.has_method("take_damage"):
		player.take_damage(999.0)  # 碰撞即死
