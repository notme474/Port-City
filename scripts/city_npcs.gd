extends Node3D

## 城市行人系统：从 RoadManager 读取 6 条道路控制点，在人行道上生成 24 个散步 NPC。
## 性能：① NPC 同层互不碰撞（物理上无 NPC×NPC 碰撞对）；② 85m 外停走休眠；
## ③ NPC 不投射阴影；④ 路点折线行走，零导航网格/寻路开销。
## 被车撞死后在另一条路上重生（pedestrian.take_damage → relocate）。

const PED_SCRIPT := preload("res://scripts/pedestrian.gd")
const MODELS := ["Barbarian", "Mage", "Rogue", "Rogue_Hooded"]   # 避开主角的 Knight
const COUNT := 24
const SIDE_DIST := 5.5          # 距道路中线的人行道偏移

var _routes: Array = []         # Array[Dictionary] {pts: Array[Vector3], walk: Array[bool]}

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_collect_routes()
	for i in COUNT:
		_spawn(i)

# ---------- 收集道路折线 ----------
func _collect_routes() -> void:
	var rm := get_tree().current_scene.get_node_or_null("RoadManager")
	if rm:
		for road in rm.get_children():
			var pts: Array[Vector3] = []
			for rp in road.get_children():
				if rp is Node3D:
					pts.append((rp as Node3D).global_position)
			if pts.size() < 2:
				continue
			var walk: Array[bool] = []
			var any_walk := false
			for k in range(pts.size() - 1):
				# 相邻控制点高差 >3m 视为高架/匝道突变，行人不上桥，在路口折返
				var ok: bool = absf(pts[k + 1].y - pts[k].y) < 3.0
				walk.append(ok)
				any_walk = any_walk or ok
			if any_walk:
				_routes.append({"pts": pts, "walk": walk})
	# 兜底：道路系统缺失时用主城环线（不应发生）
	if _routes.is_empty():
		var fallback: Array[Vector3] = [
			Vector3(-200, 6, -200), Vector3(200, 6, -200),
			Vector3(200, 6, 200), Vector3(-200, 6, 200)]
		_routes.append({"pts": fallback, "walk": [true, true, true]})

# ---------- 生成行人 ----------
func _spawn(i: int) -> void:
	var r: Dictionary = _routes[i % _routes.size()]
	var pts: Array = r["pts"]
	var walk: Array = r["walk"]
	var seg := _random_walkable(walk)

	var body := CharacterBody3D.new()
	body.name = "行人_%02d" % i
	body.set_script(PED_SCRIPT)
	add_child(body)

	# 胶囊碰撞（脚底在 body 原点）
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	body.add_child(col)

	# 外观（4 种 kaykit 角色，与主角同骨骼动画体系）
	var model_name: String = MODELS[i % MODELS.size()]
	var ps: PackedScene = load("res://models/kaykit/%s.glb" % model_name)
	var mdl: Node3D = ps.instantiate()
	body.add_child(mdl)
	ModelUtil.snap_to_ground(mdl, 1.0, 0.0)
	_disable_shadow(mdl)
	var ap: AnimationPlayer = mdl.find_child("AnimationPlayer", true, false)
	if ap:
		ap.play("Idle")

	# 两侧人行道对向分流，加一点随机抖动避免排成一条线
	var side_sign: float = 1.0 if i % 2 == 0 else -1.0
	var side := SIDE_DIST * side_sign + randf_range(-0.7, 0.7)
	body.setup(ap, pts, walk, seg, side)
	body.walk_speed = randf_range(1.1, 2.0)

	# 初始位置：段内随机进度 + 人行道偏移
	var t := randf()
	var a: Vector3 = pts[seg]
	var b: Vector3 = pts[seg + 1]
	var start3 := a.lerp(b, t) + _left_of(a, b) * side
	body.teleport_to(Vector3(start3.x, 0, start3.z))
	body.rotation.y = randf() * TAU

# 行人被撞"死亡"后：换到另一条路的随机段复活
func relocate(body: CharacterBody3D) -> void:
	if _routes.is_empty():
		return
	var r: Dictionary = _routes.pick_random()
	var pts: Array = r["pts"]
	var walk: Array = r["walk"]
	var seg := _random_walkable(walk)
	body.route = pts
	body.walkable = walk
	body.seg = seg
	body.dir = 1
	body.side = SIDE_DIST * (1.0 if randf() < 0.5 else -1.0) + randf_range(-0.7, 0.7)
	body.walk_speed = randf_range(1.1, 2.0)
	var target: Vector3 = pts[seg] + _left_of(pts[seg], pts[seg + 1]) * body.side
	body.teleport_to(Vector3(target.x, 0, target.z))
	body.rotation.y = randf() * TAU

func _random_walkable(walk: Array) -> int:
	var cand: Array[int] = []
	for k in range(walk.size()):
		if walk[k]:
			cand.append(k)
	return cand[randi() % cand.size()] if not cand.is_empty() else 0

func _left_of(a: Vector3, b: Vector3) -> Vector3:
	var v := Vector2(b.x - a.x, b.z - a.z)
	if v.length() < 0.01:
		return Vector3.ZERO
	v = v.normalized()
	return Vector3(-v.y, 0.0, v.x)

## NPC 不投射平行光阴影（24 个动态角色阴影收益小、开销大；模型本身有明暗着色）
func _disable_shadow(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_shadow(c)
