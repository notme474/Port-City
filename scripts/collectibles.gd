extends Node3D
## 隐藏包裹：20 个发光粉色八面体散落在全城（含东岸新区/码头/离岛）。
## 靠近 2.2m 自动吸取，每个 +500 金币；找齐触发"港城之主"成就（10 万大奖）。
## 位置射线贴地；进度存档；不在小地图标注（真正的探索收集品）。

const REWARD := 500
const TOTAL := 20
const RISE := 1.3            # 漂浮高度（地面以上）

# 20 个包裹坐标 [x, z]
const SPOTS := [
	[400, -200], [500, -205], [600, -150], [420, -120],
	[560, -80], [460, -40], [620, -36], [400, 20],
	[520, 24], [600, 16], [468, -164], [540, -160],
	[60, -100], [-100, 60], [240, 120], [0, -180],
	[760, 420], [775, 405], [-1050, -700], [1150, -300],
]

var player: Node
var stats: Node
var _found: Array = []
var _items: Array[Node3D] = []
var _spin_t := 0.0

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	stats = get_parent().get_node_or_null("StatsSystem")
	for i in SPOTS.size():
		if _found.has(i):
			continue
		_spawn(i, float(SPOTS[i][0]), float(SPOTS[i][1]))

func _process(delta: float) -> void:
	_spin_t += delta
	for it in _items:
		if is_instance_valid(it):
			it.rotation.y += delta * 1.6
			it.position.y = it.get_meta("base_y", 0.0) + sin(_spin_t * 2.2 + it.get_meta("phase", 0.0)) * 0.22

func _spawn(idx: int, x: float, z: float) -> void:
	var gy := _ground_y(x, z)
	var holder := Node3D.new()
	holder.set_meta("idx", idx)
	holder.set_meta("base_y", gy + RISE)
	holder.set_meta("phase", float(idx) * 0.7)
	holder.position = Vector3(x, gy + RISE, z)
	add_child(holder)
	# 发光八面体
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.65)
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.25
	mat.metallic = 0.2
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	# PrismMesh 默认三棱柱，用六面锥体近似宝石；尺寸 0.9
	pm.size = Vector3(0.9, 0.9, 0.9)
	mi.mesh = pm
	mi.material_override = mat
	holder.add_child(mi)
	# 点光晕
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.3, 0.7)
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	holder.add_child(lamp)
	# 触发区
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 2.2
	cs.shape = sh
	area.add_child(cs)
	area.collision_layer = 0
	area.collision_mask = 1
	holder.add_child(area)
	area.body_entered.connect(func(b): _collect(holder, b))
	_items.append(holder)

func _collect(holder: Node3D, body: Node) -> void:
	if not is_instance_valid(holder) or not body.is_in_group("player"):
		return
	var idx: int = holder.get_meta("idx")
	if _found.has(idx):
		return
	_found.append(idx)
	_items.erase(holder)
	holder.queue_free()
	# 奖励
	if player and "coins" in player:
		player.coins += REWARD
		player.coin_collected.emit(player.coins)
	if stats:
		stats.add_stat("packages", 1)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_banner"):
		hud.show_banner("隐藏包裹  %d / %d" % [_found.size(), TOTAL], "+%d 金币" % REWARD)

func _ground_y(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -20.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else 5.95

# ---------- 存档 ----------
func get_save() -> Dictionary:
	return {"packages_found": _found}

func set_save(d: Dictionary) -> void:
	_found = (d.get("packages_found", []) as Array).duplicate()
	# 若包裹已生成（存档恢复晚于 _setup），立即移除已收集的并补生成缺失未收集的
	if is_inside_tree():
		for it in _items.duplicate():
			if is_instance_valid(it) and _found.has(int(it.get_meta("idx"))):
				_items.erase(it)
				it.queue_free()
