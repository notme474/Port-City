extends Node3D
## 手雷：按 G 投掷（代码注册按键，无需改项目输入映射）。
## 抛物线物理体（layer 2：撞墙与地面但不绊到玩家/车辆），1.8 秒后爆炸，
## 8m 球形范围伤害敌人（沿父链调 bullet_hit），近距离波及玩家自身。
## 初始 3 颗，每 45 秒补一颗，上限 5。

const MAX_GRENADES := 5
const FUSE := 1.8
const BLAST_R := 8.0
const ENEMY_DMG := 130.0
const SELF_DMG := 55.0
const RESUPPLY := 45.0

var player: Node
var view: Node3D
var grenades := 3
var _resupply_t := RESUPPLY
var _cd := 0.0
var _live: Array[Dictionary] = []   # {body, t}
var _fx: Array[Dictionary] = []     # {node, sphere, light, t}

func _ready() -> void:
	# 注册 G 键动作
	if not InputMap.has_action("throw_grenade"):
		InputMap.add_action("throw_grenade")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event("throw_grenade", ev)
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	view = get_parent().get_node_or_null("View")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw_grenade"):
		_throw()

func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	# 补给
	if grenades < MAX_GRENADES:
		_resupply_t -= delta
		if _resupply_t <= 0.0:
			grenades += 1
			_resupply_t = RESUPPLY
			_toast("手雷补给  x%d" % grenades, Color(0.6, 0.9, 0.5))
	# 引信
	for i in range(_live.size() - 1, -1, -1):
		var g: Dictionary = _live[i]
		g["t"] = float(g["t"]) - delta
		if float(g["t"]) <= 0.0:
			var body: RigidBody3D = g["body"]
			if is_instance_valid(body):
				_explode(body.global_position)
				body.queue_free()
			_live.remove_at(i)
	# 爆炸特效
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f["t"] = float(f["t"]) - delta
		var k: float = 1.0 - clampf(float(f["t"]) / 0.32, 0.0, 1.0)
		var node: Node3D = f["node"]
		if is_instance_valid(node):
			var s: float = lerp(0.5, BLAST_R * 1.4, k)
			node.scale = Vector3.ONE * s
			var mat: StandardMaterial3D = (f["sphere"] as MeshInstance3D).material_override
			mat.albedo_color.a = (1.0 - k) * 0.8
			(f["light"] as OmniLight3D).light_energy = (1.0 - k) * 14.0
		if float(f["t"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_fx.remove_at(i)

func _throw() -> void:
	if player == null or _cd > 0.0:
		return
	if "input_locked" in player and player.input_locked:
		return
	if grenades <= 0:
		_toast("没有手雷了，等待补给…", Color(1, 0.5, 0.3))
		_cd = 0.5
		return
	grenades -= 1
	_cd = 1.0
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.bounce = 0.25
	body.mass = 1.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.28, 0.16)
	mat.roughness = 0.5
	mi.material_override = mat
	body.add_child(mi)
	# 红色指示灯（引信感）
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.2, 0.1)
	lamp.light_energy = 2.0
	lamp.omni_range = 2.5
	body.add_child(lamp)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.16
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = player.global_position + Vector3.UP * 1.35
	# 朝向：驾驶中用车头，否则用玩家朝向
	var fwd: Vector3 = -player.global_transform.basis.z
	if view and "chase" in view and view.chase != null:
		fwd = -view.chase.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	body.linear_velocity = fwd * 15.0 + Vector3.UP * 5.5
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_live.append({"body": body, "t": FUSE})
	_toast("手雷  x%d" % grenades, Color(1, 0.6, 0.3))

func _explode(pos: Vector3) -> void:
	_spawn_fx(pos)
	var sp := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BLAST_R
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 7   # 1 世界 / 2 敌人命中区 / 4 行人
	var hits: Array = sp.intersect_shape(params)
	var npc_killed := 0
	var damaged: Array = []   # 同一实体多个命中区（头/身）只结算一次
	for h in hits:
		var node: Object = h.collider if h is Dictionary else null
		if node == null:
			continue
		if node is Node and (node as Node).is_in_group("player"):
			continue   # 玩家单独按距离算
		# 行人：炸倒并计入通缉
		if node is Node and (node as Node).is_in_group("npc"):
			if node.has_method("take_damage"):
				node.take_damage(100.0)
				npc_killed += 1
			continue
		var d := 0.0
		if node is Node3D:
			d = (node as Node3D).global_position.distance_to(pos)
		var dmg := ENEMY_DMG * (1.0 - clampf(d / BLAST_R, 0.0, 1.0))
		# 沿父链找可伤害实体（HitArea -> GangEnemy 等）
		var cur: Node = node if node is Node else null
		var hops := 0
		while cur != null and hops < 4:
			if cur.has_method("bullet_hit"):
				if not damaged.has(cur):
					damaged.append(cur)
					cur.bullet_hit(dmg)
				break
			cur = cur.get_parent()
			hops += 1
	# 误伤行人 → 通缉（爆炸行凶直接 2 星封顶）
	if npc_killed > 0:
		var wp := get_parent().get_node_or_null("WantedPolice")
		if wp and wp.has_method("_add_star"):
			wp._add_star(mini(2, npc_killed))
		_toast("爆炸误伤行人！  通缉 +%d" % mini(2, npc_killed), Color(1, 0.3, 0.3))
	# 玩家自伤
	if player and is_instance_valid(player):
		var pd: float = Vector2(player.global_position.x - pos.x,
			player.global_position.z - pos.z).length()
		if pd < BLAST_R:
			var self_dmg := SELF_DMG * (1.0 - pd / BLAST_R)
			if self_dmg >= 8.0 and player.has_method("take_damage"):
				player.take_damage(self_dmg)
		if pd < 26.0 and view and view.has_method("add_shake"):
			view.add_shake(0.35 * (1.0 - clampf(pd / 26.0, 0.0, 1.0)))

func _spawn_fx(pos: Vector3) -> void:
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	node.add_child(mi)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.6, 0.25)
	lamp.light_energy = 14.0
	lamp.omni_range = 24.0
	node.add_child(lamp)
	_fx.append({"node": node, "sphere": mi, "light": lamp, "t": 0.32})

func _toast(txt: String, col: Color) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_banner"):
		hud._show_banner(txt, col, 0.9)
