extends Node3D

## 汽车岛交互：走近车辆按 F 上车，驾驶中再按 F 下车
##
## player / view / vehicles_root 都不必在场景里手动连线：
## _ready() 会自动在场景中查找（防止编辑器保存场景时把覆盖属性冲掉）

@export var player: CharacterBody3D
@export var view: Node3D
@export var vehicles_root: Node3D
@export var interact_radius := 6.5                    ## 可上车的水平距离（米）

var _driving: CarVehicle = null
var _nearest: CarVehicle = null


func _ready() -> void:
	_resolve_refs()
	# 节点有时序差异，下一帧再兜底一次
	call_deferred("_resolve_refs")


## 自动绑定玩家 / 相机 / 车辆根，不依赖 tscn 里的 NodePath 覆盖
func _resolve_refs() -> void:
	if player == null:
		player = get_node_or_null("../Player") as CharacterBody3D
		if player == null:
			var found := get_tree().get_nodes_in_group("player")
			if not found.is_empty():
				player = found[0] as CharacterBody3D
	if view == null:
		view = get_node_or_null("../View") as Node3D
	if vehicles_root == null:
		# 优先找名为“车辆”的直接子节点
		vehicles_root = get_node_or_null("车辆") as Node3D
		if vehicles_root == null:
			# 否则找直接子节点中含车辆最多的那个
			var best: Node3D = null
			var best_n := 0
			for child in get_children():
				if child is Node3D:
					var n := 0
					for grand in child.get_children():
						if grand is CarVehicle:
							n += 1
					if n > best_n:
						best_n = n
						best = child
			vehicles_root = best


func _physics_process(_delta: float) -> void:
	# 编辑器回写等极端情况下引用丢失，每帧尝试恢复
	if player == null or vehicles_root == null:
		_resolve_refs()

	if _driving != null:
		if Input.is_action_just_pressed("interact"):
			_exit_vehicle()
		return

	_nearest = _find_nearest()
	if _nearest != null and Input.is_action_just_pressed("interact"):
		_enter_vehicle(_nearest)


## 找到玩家附近最近的车辆（只算水平距离，不吃高低差）
func _find_nearest() -> CarVehicle:
	if player == null or vehicles_root == null:
		return null
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var best: CarVehicle = null
	var best_dist := interact_radius
	for child in vehicles_root.get_children():
		if child is CarVehicle:
			var cp := Vector2(child.global_position.x, child.global_position.z)
			var d := pp.distance_to(cp)
			if d < best_dist:
				best_dist = d
				best = child
	return best


func _enter_vehicle(car: CarVehicle) -> void:
	_driving = car
	car.driver = player
	car.stop()
	if view != null:
		# 追尾相机：跟车头方向、抬高、倒车自动转镜头
		if view.has_method("start_chase"):
			view.start_chase(car)
		elif car.view_target != null:
			view.target = car.view_target
	set_player_active(false)


func _exit_vehicle() -> void:
	var car := _driving
	_driving = null
	car.driver = null
	car.stop()

	# 站到车身左侧
	var left := -car.global_transform.basis.x
	player.global_position = car.global_position + left * 2.4 + Vector3.UP * 0.8
	player.velocity = Vector3.ZERO
	player.rotation.y = car.rotation.y

	if view != null:
		if view.has_method("end_chase"):
			view.end_chase()
		view.target = player
	set_player_active(true)


func set_player_active(active: bool) -> void:
	if player == null:
		return
	player.visible = active
	player.set_physics_process(active)
	player.set_process(active)
	player.collision_layer = 1 if active else 0
	# 步行时 mask 含 layer 4（行人 NPC）；上车后关闭全部物理
	player.collision_mask = (1 | 4) if active else 0
