extends Node3D
## 帮派据点战：3 个偏远据点（码头/荒岛/绿岛），每处 3 波帮派分子。
## 靠近据点 34m 自动开战；清光一波 2 秒后刷下一波；全清给奖金并计入成就。
## 已清剿据点存档，读档后保持平静。地面红圈 + 紫色地标光柱引导。

const GANG := preload("res://scripts/gang_enemy.gd")
const CAMP_R := 20.0
const TRIGGER_R := 34.0
const WAVES: Array = [3, 4, 5]
const REWARD := 5000

var player: Node
var stats: Node
var minimap: Node

# name / 中心坐标
var CAMPS: Array = [
	{"name": "码头仓库帮", "x": 720.0, "z": 380.0},
	{"name": "荒岛营地", "x": -1030.0, "z": -680.0},
	{"name": "东岸走私帮", "x": 1130.0, "z": -320.0},
]
# 每个据点运行态
var _st: Array = []

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	stats = get_parent().get_node_or_null("StatsSystem")
	minimap = get_parent().get_node_or_null("Minimap")
	for i in CAMPS.size():
		var c: Dictionary = CAMPS[i]
		var gy := _gy(float(c["x"]), float(c["z"]))
		var ring := _make_ring(gy)
		ring.position = Vector3(float(c["x"]), gy, float(c["z"]))
		add_child(ring)
		var beam := _make_beam(gy)
		beam.position = Vector3(float(c["x"]), gy, float(c["z"]))
		add_child(beam)
		_st.append({"state": 0, "wave": 0, "remaining": 0, "next_t": 0.0,
			"ring": ring, "beam": beam, "gy": gy, "enemies": []})
	# 小地图常驻显示未清剿据点
	if minimap:
		for i in CAMPS.size():
			minimap.add_marker("camp_%d" % i,
				Vector3(float(CAMPS[i]["x"]), 0.0, float(CAMPS[i]["z"])),
				Color(0.85, 0.25, 1.0), "帮派据点")

func _process(delta: float) -> void:
	if player == null:
		return
	for i in _st.size():
		var s: Dictionary = _st[i]
		var c: Dictionary = CAMPS[i]
		var hd := _hdist(Vector3(float(c["x"]), 0, float(c["z"])))
		match int(s["state"]):
			0:
				if hd < TRIGGER_R:
					_start_camp(i)
			1:
				if int(s["remaining"]) <= 0:
					s["next_t"] = float(s["next_t"]) - delta
					if float(s["next_t"]) <= 0.0:
						_next_wave(i)
			2:
				pass

# ---------- 开战 / 波次 ----------
func _start_camp(i: int) -> void:
	var s: Dictionary = _st[i]
	s["state"] = 1
	s["wave"] = 0
	_banner("帮派据点！清剿 %s" % str(CAMPS[i]["name"]), "共 %d 波敌人" % WAVES.size(), Color(1, 0.3, 0.3), 2.6)
	if minimap:
		minimap.add_marker("camp_%d" % i, Vector3(float(CAMPS[i]["x"]), float(s["gy"]), float(CAMPS[i]["z"])), Color.RED, "帮派据点")
	_spawn_wave(i)

func _next_wave(i: int) -> void:
	var s: Dictionary = _st[i]
	var w: int = int(s["wave"])
	if w >= WAVES.size():
		_clear_camp(i)
		return
	_spawn_wave(i)

func _spawn_wave(i: int) -> void:
	var s: Dictionary = _st[i]
	var c: Dictionary = CAMPS[i]
	var w: int = int(s["wave"])
	var count: int = WAVES[w]
	var gy: float = float(s["gy"])
	var ranged_n: int = clampi(w, 0, count)   # 波0无枪手，波1一个，波2两个
	for k in count:
		var ang := TAU * float(k) / float(count) + float(i) * 0.7
		var r := 7.0 + float((k + w) % 3) * 3.0
		var ex := float(c["x"]) + cos(ang) * r
		var ez := float(c["z"]) + sin(ang) * r
		var egy := _gy(ex, ez)
		if absf(egy - gy) > 3.0:
			egy = gy   # 射线打到建筑/异常时回退据点高度
		var e := Node3D.new()
		e.set_script(GANG)
		e.position = Vector3(ex, egy, ez)
		add_child(e)
		# setup 需在节点就绪前后调用均可（变量直接赋值）
		e.setup(player, egy, Vector3(ex, gy, ez), k < ranged_n)
		var idx := i
		e.died.connect(func(n): _on_enemy_died(idx, n.ranged))
		(s["enemies"] as Array).append(e)
	s["remaining"] = count
	var sub := "%d 名帮派分子" % count
	if ranged_n > 0:
		sub += "（%d 名枪手）" % ranged_n
	_banner("第 %d / %d 波" % [w + 1, WAVES.size()], sub, Color(1, 0.45, 0.3), 1.6)

func _on_enemy_died(i: int, is_ranged: bool = false) -> void:
	var s: Dictionary = _st[i]
	if int(s["state"]) != 1:
		return
	s["remaining"] = int(s["remaining"]) - 1
	# 击杀掉落现金：枪手更富有
	var drop_chance := 0.5 if is_ranged else 0.3
	var drop_amt := 150 if is_ranged else 100
	if randf() < drop_chance and player and "coins" in player:
		player.coins += drop_amt
		player.coin_collected.emit(player.coins)
	if int(s["remaining"]) <= 0:
		var w: int = int(s["wave"]) + 1
		s["wave"] = w
		if w >= WAVES.size():
			s["next_t"] = 0.4
			_banner("最后一波已清！", "", Color(0.4, 1, 0.5))
		else:
			s["next_t"] = 2.0
			_banner("第 %d 波清灭" % w, "下一波即将到来…", Color(1, 0.7, 0.3))

func _clear_camp(i: int) -> void:
	var s: Dictionary = _st[i]
	s["state"] = 2
	var c: Dictionary = CAMPS[i]
	if player and "coins" in player:
		player.coins += REWARD
		player.coin_collected.emit(player.coins)
	if stats:
		stats.add_stat("camps_cleared", 1)
	if minimap:
		minimap.remove_marker("camp_%d" % i)
	# 红圈变绿后淡出
	var ring: MeshInstance3D = s["ring"]
	if ring and ring.material_override:
		var m := (ring.material_override as StandardMaterial3D)
		m.albedo_color = Color(0.2, 0.9, 0.4, 0.16)
		m.emission = Color(0.2, 0.9, 0.4)
		m.emission_energy_multiplier = 0.4
	var beam: MeshInstance3D = s["beam"]
	if beam:
		var bm2 := StandardMaterial3D.new()
		bm2.albedo_color = Color(0.2, 0.9, 0.4, 0.12)
		bm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm2.emission_enabled = true
		bm2.emission = Color(0.2, 0.9, 0.4)
		bm2.emission_energy_multiplier = 0.3
		bm2.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bm2
	_banner("据点已肃清 · %s" % str(c["name"]), "+%d 金币" % REWARD, Color(0.3, 1, 0.5), 3.0)

# ---------- 视觉 ----------
func _make_ring(gy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = CAMP_R - 0.7
	tm.outer_radius = CAMP_R
	mi.mesh = tm
	mi.rotation.x = deg_to_rad(90.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.15, 0.15)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(1, 0.1, 0.1)
	m.emission_energy_multiplier = 1.0
	mi.material_override = m
	mi.position.y = 0.35
	return mi

func _make_beam(_gy2: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 30.0
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.2, 1.0, 0.07)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(0.7, 0.2, 1.0)
	m.emission_energy_multiplier = 0.18
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position.y = 15.0
	return mi

func _hdist(p: Vector3) -> float:
	if player == null:
		return 9999.0
	var pp: Vector3 = player.global_position
	return Vector2(pp.x - p.x, pp.z - p.z).length()

func _gy(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -30.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else 5.95

func _banner(title: String, sub: String, col: Color, dur := 1.6) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_banner"):
		hud._show_banner("%s   %s" % [title, sub] if sub != "" else title, col, dur)

# ---------- 存档 ----------
func get_save() -> Dictionary:
	var cleared: Array = []
	for s in _st:
		cleared.append(int((s as Dictionary)["state"]) == 2)
	return {"camps_cleared": cleared}

func set_save(d: Dictionary) -> void:
	var arr: Array = d.get("camps_cleared", [])
	# 节点可能尚未建好（_setup 有两帧延迟），延迟处理
	call_deferred("_apply_save", arr)

func _apply_save(arr: Array) -> void:
	# _setup 有两帧延迟，等其建好 _st 再恢复清剿状态
	await get_tree().process_frame
	await get_tree().process_frame
	for i in mini(arr.size(), _st.size()):
		if bool(arr[i]):
			var s: Dictionary = _st[i]
			s["state"] = 2
			var ring: MeshInstance3D = s["ring"]
			if ring and ring.material_override:
				(ring.material_override as StandardMaterial3D).albedo_color = Color(0.2, 0.9, 0.4)
				(ring.material_override as StandardMaterial3D).emission = Color(0.2, 0.9, 0.4)
				(ring.material_override as StandardMaterial3D).emission_energy_multiplier = 1.0
			if minimap:
				minimap.remove_marker("camp_%d" % i)
