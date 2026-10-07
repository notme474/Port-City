extends Node3D

## 通缉度系统：撞NPC涨星→警车追→甩掉/被抓掉星
## 星星 0~5，越高警车越多越快；脱离警车视野 8 秒降一星

const STAR_TIME := 8.0           # 无目击持续 8 秒降一星
const MAX_STARS := 5
const CHASE_SPEED := 16.0        # 警车移速（比玩家跑快，比车慢）
const CAUGHT_DIST := 3.0         # 抓到距离
const ESCAPE_DIST := 80.0        # 脱离视野距离

var player: Node3D
var hud: Control
var _stars := 0
var _star_t := 0.0               # 当前星级剩余"冷却"时间
var _police_cars: Array[CharacterBody3D] = []
var _npc_hits := 0
var _wanted_max := 0
var _chasing := false
var _caught_t := 0.0

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	hud = get_parent().get_node_or_null("HUD")
	# 监听所有车的碰撞（撞NPC涨星）
	_watch_cars()

func _watch_cars() -> void:
	# 等 city_cars 建完
	await get_tree().create_timer(1.5).timeout
	var cc = get_parent().get_node_or_null("CityCars")
	if cc == null:
		return
	var mgr = cc.get_node_or_null("CityCarManager")
	if mgr == null:
		return
	var root = mgr.get_node_or_null("车辆")
	if root == null:
		return
	for car in root.get_children():
		if car is CharacterBody3D:
			# 给每辆车加一个碰撞检测 Area（撞 NPC 判定）
			var area := Area3D.new()
			area.name = "HitArea"
			area.collision_layer = 0
			area.collision_mask = 4    # NPC 在 layer 4
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.2, 1.8, 4.5)
			col.shape = box
			col.position = Vector3(0, 0.9, 0)
			area.add_child(col)
			area.body_entered.connect(_on_car_hit.bind(car))
			car.add_child(area)

func _on_car_hit(body: Node3D, _car: CharacterBody3D) -> void:
	# 撞到 NPC（带 take_damage 的 group npc）
	if body == player or not body.is_in_group("npc"):
		return
	if body.has_method("take_damage"):
		body.take_damage(30.0)
	_npc_hits += 1
	_add_star(1)
	_msg("撞人了！通缉 +1 星")

func _add_star(n: int) -> void:
	_stars = clampi(_stars + n, 0, MAX_STARS)
	_star_t = STAR_TIME
	_wanted_max = maxi(_wanted_max, _stars)
	_update_hud()
	if _stars >= 1 and not _chasing:
		_spawn_police()

func _remove_star() -> void:
	_stars = clampi(_stars - 1, 0, MAX_STARS)
	_star_t = STAR_TIME
	_update_hud()
	if _stars == 0:
		_clear_police()
		_msg("通缉解除")

func _update_hud() -> void:
	if hud and hud.has_method("_show_banner"):
		var txt := "通缉度：%s" % "★".repeat(_stars) if _stars > 0 else "通缉解除"
		var col := Color(1, 0.25, 0.3) if _stars > 0 else Color(0.4, 1, 0.5)
		hud._show_banner(txt, col, 1.2)

func _spawn_police() -> void:
	_chasing = true
	# 根据星级生成 1~3 辆警车（复用 city_cars 的 vehicle.tscn，改涂装）
	var count := clampi(_stars, 1, 3)
	for i in count:
		var car := _make_police_car(i)
		if car:
			_police_cars.append(car)
			add_child(car)
	_msg("警车出动！数量 %d" % _police_cars.size())

func _make_police_car(idx: int) -> CharacterBody3D:
	var sc: PackedScene = load("res://objects/vehicle.tscn")
	if sc == null:
		return null
	var car: CharacterBody3D = sc.instantiate()
	# 用出租车模型改黑白涂装（警车）
	var glb: PackedScene = load("res://GLB format/出租车.glb")
	car.set("model_scene", glb)
	# 出生点：玩家四周 40m 外随机方向
	var ang := randf() * TAU
	var spawn := player.global_position + Vector3(cos(ang) * 40, 0, sin(ang) * 40)
	spawn.y = _gy(spawn) + 0.5
	car.global_position = spawn
	car.rotation_degrees.y = randf() * 360.0
	# 警灯（红蓝爆闪）
	var l1 := OmniLight3D.new()
	l1.name = "警灯红"
	l1.light_color = Color(1, 0.1, 0.1)
	l1.light_energy = 0.0
	l1.omni_range = 10.0
	l1.position = Vector3(-0.5, 2.2, 0)
	car.add_child(l1)
	var l2 := OmniLight3D.new()
	l2.name = "警灯蓝"
	l2.light_color = Color(0.1, 0.3, 1.0)
	l2.light_energy = 0.0
	l2.omni_range = 10.0
	l2.position = Vector3(0.5, 2.2, 0)
	car.add_child(l2)
	# 车顶警灯条
	var bar := MeshInstance3D.new()
	bar.mesh = BoxMesh.new()
	bar.mesh.size = Vector3(1.4, 0.3, 0.5)
	bar.position = Vector3(0, 2.0, 0)
	bar.material_override = _police_mat()
	car.add_child(bar)
	return car

func _police_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.15)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.2, 0.3)
	m.emission_energy_multiplier = 1.5
	return m

func _gy(p: Vector3) -> float:
	var from := Vector3(p.x, 20.0, p.z)
	var to := Vector3(p.x, -5.0, p.z)
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0

func _physics_process(delta: float) -> void:
	if _stars == 0 or player == null:
		return
	# 无目击冷却降星
	_star_t -= delta
	if _star_t <= 0.0:
		_remove_star()
		return
	# 警车追逐
	_chase_police(delta)
	# 警灯爆闪
	_flash_lights()
	# 被抓判定
	_check_caught()

func _chase_police(delta: float) -> void:
	var player_pos := player.global_position
	var any_near := false
	for car in _police_cars:
		if not is_instance_valid(car):
			continue
		var dir := player_pos - car.global_position
		dir.y = 0
		var dist := dir.length()
		if dist < ESCAPE_DIST:
			any_near = true
		# 2m 内不再往前顶（避免穿模压到玩家身上），被抓判定由 _check_caught 负责
		if dist > 2.0:
			var speed := CHASE_SPEED * (1.0 + _stars * 0.15)   # 星级越高越快
			car.global_position += dir.normalized() * speed * delta
			car.rotation.y = atan2(dir.x, dir.z)
		# 警车贴地
		var gy := _gy(car.global_position)
		car.global_position.y = move_toward(car.global_position.y, gy, 8.0 * delta)
	if not any_near and _police_cars.size() > 0:
		# 全部脱离视野，开始降星冷却
		pass

func _flash_lights() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for car in _police_cars:
		if not is_instance_valid(car):
			continue
		var l1 = car.get_node_or_null("警灯红")
		var l2 = car.get_node_or_null("警灯蓝")
		if l1:
			l1.light_energy = 3.0 + sin(t * 12.0) * 2.5
		if l2:
			l2.light_energy = 3.0 + sin(t * 12.0 + PI) * 2.5

func _check_caught() -> void:
	for car in _police_cars:
		if not is_instance_valid(car):
			continue
		var dist := car.global_position.distance_to(player.global_position)
		if dist < CAUGHT_DIST:
			_caught_t += get_physics_process_delta_time()
			if _caught_t > 0.5:
				_busted()
				return
		else:
			_caught_t = 0.0

func _busted() -> void:
	# 被抓：扣金币 + 清通缉 + 警车撤离
	var fine := _stars * 200
	player.coins = max(0, player.coins - fine)
	player.coin_collected.emit(player.coins)
	_msg("被警察抓了！罚款 %d 金币" % fine)
	_clear_police()
	_stars = 0
	_update_hud()

func _clear_police() -> void:
	for car in _police_cars:
		if is_instance_valid(car):
			car.queue_free()
	_police_cars.clear()
	_chasing = false
	_caught_t = 0.0

func _msg(t: String) -> void:
	if hud and hud.has_method("_show_banner"):
		hud._show_banner(t, Color(1, 0.25, 0.3), 1.4)

## 外部接口：任务/商店读通缉度
func get_stars() -> int:
	return _stars

func is_wanted() -> bool:
	return _stars > 0
