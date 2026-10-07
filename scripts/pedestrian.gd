extends CharacterBody3D

## 城市行人：沿 RoadManager 路点折线在人行道上往返散步。
## 碰撞：collision_layer=4、mask 只含世界(1) → NPC 之间/与车之间零碰撞对，
## 玩家 mask 含 4 即可撞到 NPC（Godot 碰撞过滤为双向 OR，配置最少、性能最好）。
## 85m 外自动停走休眠；被车撞（通缉系统调 take_damage）倒地后在别处重生。

const ANIM_WALK := "Walking_A"
const ANIM_IDLE := "Idle"
const ANIM_DEATH := "Death_A"
const SLEEP_DIST := 85.0       # 距玩家超过此距离停止 AI 与物理移动
const STUCK_NEED := 3         # 连续 3 个检测周期（每周期 1 秒）几乎没动 → 瞬移脱困

var route: Array = []         # Array[Vector3] 折线路点（只用 x/z）
var walkable: Array = []      # Array[bool] 每段是否可走（高架突变段排除）
var seg := 0                  # 当前段索引
var dir := 1                  # 1 向前 / -1 折返
var side := 5.5               # 人行道侧移（正/负 = 路的两侧）
var walk_speed := 1.5
var anim: AnimationPlayer

var _dead := false
var _grav := 0.0
var _stuck_t := 0.0
var _stuck_n := 0
var _last_pos := Vector3.ZERO
var _is_walking_anim := false

func setup(a: AnimationPlayer, p_route: Array, p_walk: Array, p_seg: int, p_side: float) -> void:
	anim = a
	route = p_route
	walkable = p_walk
	seg = p_seg
	side = p_side

func _ready() -> void:
	add_to_group("npc")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(45.0)
	_last_pos = global_position

func _physics_process(delta: float) -> void:
	if _dead or route.is_empty():
		return
	# 远距离休眠：不走路、不做 move_and_slide（保留静态碰撞，走近即醒）
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) > SLEEP_DIST:
		if _is_walking_anim:
			_play(ANIM_IDLE)
		return

	# 前方段不可走（高架/陡坡突变）→ 在路口折返
	# 正向时身处 seg 段、反向时身处 seg-1 段
	var cur_seg: int = seg if dir > 0 else seg - 1
	if cur_seg < 0 or cur_seg >= walkable.size() or not walkable[cur_seg]:
		_flip()
		cur_seg = seg if dir > 0 else seg - 1

	var ti := seg + dir
	var target_p: Vector3 = route[ti] + _side_vec(cur_seg) * side
	var flat := Vector3(target_p.x - global_position.x, 0.0, target_p.z - global_position.z)
	var d := flat.length()
	if d < 1.4:
		_advance()
		velocity = Vector3.ZERO
		move_and_slide()
		_play(ANIM_IDLE)
		return

	# 重力 + 贴地
	_grav += 20.0 * delta
	if is_on_floor():
		_grav = 0.0
	var move_dir := flat / d
	velocity.x = move_dir.x * walk_speed
	velocity.z = move_dir.z * walk_speed
	velocity.y = -_grav
	rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), delta * 8.0)
	move_and_slide()
	_play(ANIM_WALK)
	if anim:
		anim.speed_scale = clampf(walk_speed / 1.6, 0.6, 1.6)

	# 卡墙自救：连续 3 秒位移不足 → 直接吸到目标点（路口被楼挡住时自愈）
	_stuck_t += delta
	if _stuck_t >= 1.0:
		if global_position.distance_to(_last_pos) < walk_speed * 0.45:
			_stuck_n += 1
			if _stuck_n >= STUCK_NEED:
				teleport_to(target_p)
				_stuck_n = 0
		else:
			_stuck_n = 0
		_last_pos = global_position
		_stuck_t = 0.0

func teleport_to(p: Vector3) -> void:
	var gy: float = _ground_y(p)
	global_position = Vector3(p.x, gy + 0.4, p.z)
	velocity = Vector3.ZERO
	_grav = 0.0

func _advance() -> void:
	if dir > 0:
		seg += 1
		if seg >= route.size() - 1:
			dir = -1
			seg = route.size() - 2
	else:
		seg -= 1
		if seg < 0:
			dir = 1
			seg = 0

func _flip() -> void:
	dir = -dir
	if dir > 0:
		seg = maxi(0, seg)
	else:
		seg = mini(route.size() - 2, seg)

## 当前段的"路左侧"单位向量（侧移到人行道用，折返时段不变故两侧固定）
func _side_vec(s: int) -> Vector3:
	var a: Vector3 = route[s]
	var b: Vector3 = route[s + 1]
	var v := Vector2(b.x - a.x, b.z - a.z)
	if v.length() < 0.01:
		return Vector3.ZERO
	v = v.normalized()
	return Vector3(-v.y, 0.0, v.x)

func _ground_y(p: Vector3) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, 25.0, p.z), Vector3(p.x, -5.0, p.z), 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0

func _play(nm: String) -> void:
	if anim == null:
		return
	if nm == ANIM_WALK:
		if not _is_walking_anim:
			anim.play(ANIM_WALK, 0.15)
			_is_walking_anim = true
	else:
		if _is_walking_anim:
			anim.play(ANIM_IDLE, 0.2)
			_is_walking_anim = false

## 通缉系统撞人时调用：倒地 4 秒 → 由 CityNpcs 在别处重生
func take_damage(_amount: float) -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if anim:
		anim.play(ANIM_DEATH, 0.15)
	await get_tree().create_timer(4.0).timeout
	# 请求生成器把自己安置到另一条路（模拟新人，避免原地复活穿帮）
	var owner_node := get_parent()
	if owner_node and owner_node.has_method("relocate"):
		owner_node.relocate(self)
	_dead = false
	collision_layer = 4
	collision_mask = 1
	_stuck_n = 0
	_is_walking_anim = false
	_play(ANIM_IDLE)
