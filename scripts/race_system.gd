extends Node3D
## 检查点竞速：3 条赛道分布在东岸新区路网与主城连接大道。
## 走进起点光柱开始（步行或驾车均可），依次穿过发光检查点，按用时评金/银/铜奖。
## 只显示"下一个检查点"光柱（GTA 式引导）；超时 180s 自动弃权；最佳成绩存档。

const CP_R := 9.0            # 检查点触发半径
const TIME_LIMIT := 180.0

var player: Node
var stats: Node
var minimap: Node
var rng := RandomNumberGenerator.new()

# 每条赛道：名字 / 检查点序列（最后一个为终点）/ 金 银 铜 秒阈值
var races := [
	{"name": "东岸内环", "pts": [Vector3(348, 0, -188), Vector3(604, 0, -188),
		Vector3(604, 0, -60), Vector3(540, 0, -60), Vector3(540, 0, 4),
		Vector3(412, 0, 4), Vector3(412, 0, -124), Vector3(348, 0, -188)],
		"g": 40.0, "s": 55.0, "b": 75.0},
	{"name": "东岸外环", "pts": [Vector3(348, 0, -252), Vector3(604, 0, -252),
		Vector3(604, 0, -60), Vector3(604, 0, 4), Vector3(412, 0, 4),
		Vector3(348, 0, 4), Vector3(348, 0, -124), Vector3(348, 0, -252)],
		"g": 55.0, "s": 75.0, "b": 100.0},
	{"name": "都市连线", "pts": [Vector3(333, 0, -130), Vector3(333, 0, -240),
		Vector3(412, 0, -252), Vector3(412, 0, -188), Vector3(333, 0, -130)],
		"g": 40.0, "s": 55.0, "b": 75.0},
]
var best: Array = [0.0, 0.0, 0.0]   # 每条赛道最佳秒数，0=未完成

var race_idx := -1
var cp_idx := 0
var start_ms := 0
var _start_markers: Array[Node3D] = []
var _cp_marker: Node3D
var _cp_beam: MeshInstance3D
var _cp_ring: MeshInstance3D

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	stats = get_parent().get_node_or_null("StatsSystem")
	minimap = get_parent().get_node_or_null("Minimap")
	_build_start_markers()
	_build_cp_marker()

# ---------- 起点光柱（每条赛道一个，黄色常驻） ----------
func _build_start_markers() -> void:
	for i in races.size():
		var p: Vector3 = races[i]["pts"][0]
		var gy := _gy(p.x, p.z)
		var m := _make_marker(Color(1.0, 0.82, 0.2), gy)
		m.position = Vector3(p.x, gy, p.z)
		add_child(m)
		var area: Area3D = m.get_node("Area")
		var idx := i
		area.body_entered.connect(func(b): _try_start(idx, b))
		_start_markers.append(m)

# ---------- 活动检查点光柱（单个，随目标移动） ----------
func _build_cp_marker() -> void:
	_cp_marker = Node3D.new()
	_cp_marker.visible = false
	add_child(_cp_marker)
	var beam_mat := _beam_mat(Color(0.25, 0.9, 1.0))
	_cp_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.4
	bm.bottom_radius = 1.4
	bm.height = 14.0
	_cp_beam.mesh = bm
	_cp_beam.material_override = beam_mat
	_cp_beam.position.y = 7.0
	_cp_marker.add_child(_cp_beam)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.25, 0.9, 1.0)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.25, 0.9, 1.0)
	ring_mat.emission_energy_multiplier = 1.0
	_cp_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = CP_R - 0.8
	rm.outer_radius = CP_R
	_cp_ring.mesh = rm
	_cp_ring.rotation.x = deg_to_rad(90.0)
	_cp_ring.material_override = ring_mat
	_cp_ring.position.y = 0.3
	_cp_marker.add_child(_cp_ring)
	var area := Area3D.new()
	area.name = "Area"
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = CP_R
	sh.height = 16.0
	cs.shape = sh
	cs.position.y = 7.0
	area.add_child(cs)
	area.collision_layer = 0
	area.collision_mask = 1
	_cp_marker.add_child(area)
	area.body_entered.connect(_on_cp_body)

func _make_marker(col: Color, gy: float) -> Node3D:
	var m := Node3D.new()
	var beam_mat := _beam_mat(col)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.6
	bm.bottom_radius = 1.6
	bm.height = 12.0
	beam.mesh = bm
	beam.material_override = beam_mat
	beam.position.y = 6.0
	m.add_child(beam)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 3.4
	rm.outer_radius = 4.2
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = col
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.emission = col
	rmat.emission_energy_multiplier = 1.0
	ring.mesh = rm
	ring.rotation.x = deg_to_rad(90.0)
	ring.material_override = rmat
	ring.position.y = 0.3
	m.add_child(ring)
	var area := Area3D.new()
	area.name = "Area"
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 5.0
	sh.height = 14.0
	cs.shape = sh
	cs.position.y = 6.0
	area.add_child(cs)
	area.collision_layer = 0
	area.collision_mask = 1
	m.add_child(area)
	return m

func _beam_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.08)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.18
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---------- 开始 / 推进 / 结束 ----------
func _try_start(idx: int, body: Node) -> void:
	if race_idx != -1:
		return
	if not _is_player_or_car(body, (races[idx]["pts"][0] as Vector3)):
		return
	race_idx = idx
	cp_idx = 1   # pts[0] 是起点，第一个目标是 pts[1]
	start_ms = Time.get_ticks_msec()
	_place_cp()
	_banner("%s · 出发！" % str(races[idx]["name"]), "穿过 %d 个检查点" % ((races[idx]["pts"] as Array).size() - 1), Color(0.25, 0.9, 1.0))

func _place_cp() -> void:
	var pts: Array = races[race_idx]["pts"]
	if cp_idx >= pts.size():
		return
	var p: Vector3 = pts[cp_idx]
	var gy := _gy(p.x, p.z)
	_cp_marker.visible = true
	_cp_marker.position = Vector3(p.x, gy, p.z)
	# 终点变金色
	var is_final := cp_idx == pts.size() - 1
	var col := Color(1.0, 0.8, 0.25) if is_final else Color(0.25, 0.9, 1.0)
	_cp_beam.material_override = _beam_mat(col)
	(_cp_ring.material_override as StandardMaterial3D).albedo_color = col
	(_cp_ring.material_override as StandardMaterial3D).emission = col
	if minimap and minimap.has_method("add_marker"):
		minimap.add_marker("race_cp", Vector3(p.x, gy, p.z), col, "检查点")

func _on_cp_body(body: Node) -> void:
	if race_idx == -1:
		return
	var pts: Array = races[race_idx]["pts"]
	var p: Vector3 = pts[cp_idx]
	if not _is_player_or_car(body, p):
		return
	cp_idx += 1
	if cp_idx >= pts.size():
		_finish()
	else:
		var t := _elapsed()
		_banner("检查点 %d / %d" % [cp_idx, pts.size() - 1], "用时 %.1f 秒" % t, Color(0.25, 0.9, 1.0))
		_place_cp()

func _finish() -> void:
	var t := _elapsed()
	var r: Dictionary = races[race_idx]
	var reward := 600
	var grade := "完赛"
	var col := Color(0.8, 0.8, 0.8)
	if t <= float(r["g"]):
		reward = 4000; grade = "金牌"; col = Color(1.0, 0.8, 0.25)
	elif t <= float(r["s"]):
		reward = 2500; grade = "银牌"; col = Color(0.85, 0.85, 0.9)
	elif t <= float(r["b"]):
		reward = 1500; grade = "铜牌"; col = Color(0.85, 0.55, 0.3)
	if best[race_idx] == 0.0 or t < best[race_idx]:
		best[race_idx] = t
	if player and "coins" in player:
		player.coins += reward
		player.coin_collected.emit(player.coins)
	if stats:
		stats.add_stat("races_done", 1)
	if minimap:
		minimap.remove_marker("race_cp")
	_cp_marker.visible = false
	_banner("%s · %s  %.1f 秒" % [str(r["name"]), grade, t], "+%d 金币" % reward, col, 3.0)
	race_idx = -1

func _process(_delta: float) -> void:
	if race_idx == -1:
		return
	var t := _elapsed()
	if t > TIME_LIMIT:
		_cancel("超时弃权")
		return
	# 距离当前点太远（>260m）判弃权
	var pts: Array = races[race_idx]["pts"]
	if player and cp_idx < pts.size():
		var p: Vector3 = pts[cp_idx]
		if player.global_position.distance_to(Vector3(p.x, player.global_position.y, p.z)) > 260.0:
			_cancel("偏离赛道太远")

func _cancel(reason: String) -> void:
	_banner("竞速取消", reason, Color(1, 0.5, 0.4), 2.0)
	if minimap:
		minimap.remove_marker("race_cp")
	_cp_marker.visible = false
	race_idx = -1

func _elapsed() -> float:
	return (Time.get_ticks_msec() - start_ms) / 1000.0

## body 是玩家本人，或玩家（步行/在车中）距该点足够近
func _is_player_or_car(body: Node, point: Vector3) -> bool:
	if body.is_in_group("player"):
		return true
	if player == null:
		return false
	return player.global_position.distance_to(Vector3(point.x, player.global_position.y, point.z)) < CP_R + 6.0

func _gy(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -10.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else 5.95

func _banner(title: String, sub: String, col: Color, dur := 1.6) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_banner"):
		if sub != "":
			hud._show_banner("%s   %s" % [title, sub], col, dur)
		else:
			hud._show_banner(title, col, dur)

# ---------- 存档 ----------
func get_save() -> Dictionary:
	return {"race_best": best}

func set_save(d: Dictionary) -> void:
	var arr: Array = d.get("race_best", [])
	for i in mini(arr.size(), best.size()):
		best[i] = float(arr[i])
