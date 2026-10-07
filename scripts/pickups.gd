extends Node3D
## 世界物资：血包/弹药/钱袋/消星警星，散布全城路口与东岸新区。
## 靠近 2m 自动拾取；普通物资 30~70 秒原位重生，消星 120 秒。漂浮旋转发光。

const PICK_R := 2.0

var player: Node
var stats: Node
var _rng := RandomNumberGenerator.new()
var _drops: Array[Dictionary] = []

# 类型：颜色 / 形状 / 重生秒
const TYPES := {
	"hp":    {"col": Color(0.3, 1.0, 0.42), "shape": "box",  "resp": 45.0},
	"ammo":  {"col": Color(1.0, 0.62, 0.2), "shape": "flat", "resp": 40.0},
	"coins": {"col": Color(1.0, 0.85, 0.3), "shape": "gem",  "resp": 30.0},
	"star":  {"col": Color(0.35, 0.62, 1.0), "shape": "ball", "resp": 120.0},
}
# [x, z, 类型权重索引] 26 个点位
const SPOTS := [
	[60, 40, 0], [120, 40, 1], [-60, -60, 0], [-120, 120, 2],
	[180, -60, 1], [240, 40, 0], [-180, -100, 2], [60, -180, 0],
	[300, -200, 1], [0, 120, 2], [-60, 200, 0], [120, 180, 1],
	[410, -190, 0], [530, -190, 1], [410, -60, 2], [530, -60, 0],
	[600, -130, 1], [460, -20, 2], [580, 20, 0], [420, -250, 2],
	[620, -200, 3], [500, -250, 1], [460, -130, 0], [560, -190, 2],
	[745, 415, 2], [780, 430, 3],
]
const TYPE_KEYS := ["hp", "ammo", "coins", "star"]

func _ready() -> void:
	_rng.seed = 778899
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	stats = get_parent().get_node_or_null("StatsSystem")
	for s in SPOTS:
		_spawn(float(s[0]), float(s[1]), TYPE_KEYS[int(s[2])])

func _process(delta: float) -> void:
	for d in _drops:
		if not d["active"]:
			d["respawn_t"] = float(d["respawn_t"]) - delta
			if float(d["respawn_t"]) <= 0.0:
				_set_active(d, true)
			continue
		var h: Node3D = d["holder"]
		if is_instance_valid(h):
			h.rotation.y += delta * 1.4
			h.position.y = float(d["base_y"]) + sin(Time.get_ticks_msec() * 0.003 + d["phase"]) * 0.18

func _spawn(x: float, z: float, type: String) -> void:
	var t: Dictionary = TYPES[type]
	var gy := _ground_y(x, z)
	var holder := Node3D.new()
	holder.position = Vector3(x, gy + 1.1, z)
	add_child(holder)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = t["col"]
	mat.emission_enabled = true
	mat.emission = t["col"]
	mat.emission_energy_multiplier = 1.2
	mat.roughness = 0.35
	var mi := MeshInstance3D.new()
	var sh_name: String = t["shape"]
	match sh_name:
		"box":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.8, 0.7, 0.8)
			mi.mesh = bm
		"flat":
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.9, 0.35, 0.7)
			mi.mesh = bm2
		"gem":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.7, 0.7, 0.7)
			mi.mesh = pm
		"ball":
			var sm := SphereMesh.new()
			sm.radius = 0.42
			sm.height = 0.84
			mi.mesh = sm
	mi.material_override = mat
	holder.add_child(mi)
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = PICK_R
	cs.shape = sph
	area.add_child(cs)
	area.collision_layer = 0
	area.collision_mask = 1
	holder.add_child(area)
	var d := {"type": type, "holder": holder, "area": area, "mi": mi,
		"active": true, "respawn_t": 0.0, "base_y": gy + 1.1,
		"phase": _rng.randf_range(0, TAU), "col": t["col"], "resp": float(t["resp"])}
	area.body_entered.connect(func(b): _pickup(d, b))
	_drops.append(d)

func _set_active(d: Dictionary, on: bool) -> void:
	d["active"] = on
	if is_instance_valid(d["holder"]):
		d["holder"].visible = on
		(d["area"] as Area3D).monitorable = on
		(d["area"] as Area3D).monitoring = on
	if on:
		d["respawn_t"] = 0.0
	else:
		d["respawn_t"] = float(d["resp"])

func _pickup(d: Dictionary, body: Node) -> void:
	if not bool(d["active"]) or not body.is_in_group("player"):
		return
	match String(d["type"]):
		"hp":
			if player and "hp" in player:
				if player.hp >= player.max_hp:
					return   # 满血不浪费血包
				player.hp = minf(player.max_hp, player.hp + 30.0)
				player.hp_changed.emit(player.hp, player.max_hp)
			_toast("医疗包  +30 生命", d["col"])
		"ammo":
			var ws := player.get_node_or_null("WeaponSystem") if player else null
			if ws and ws.has_method("add_ammo_all"):
				ws.add_ammo_all(0.3)
			_toast("弹药补给  +备弹", d["col"])
		"coins":
			if player and "coins" in player:
				player.coins += 150
				player.coin_collected.emit(player.coins)
			_toast("钱袋  +150 金币", d["col"])
		"star":
			var wp := get_parent().get_node_or_null("WantedPolice")
			if wp:
				if wp.get_stars() <= 0:
					return   # 没通缉不浪费警星
				wp._remove_star()
			_toast("贿赂警星  通缉 -1", d["col"])
	if stats:
		stats.add_stat("pickups", 1)
	_set_active(d, false)

func _toast(txt: String, col: Color) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("_show_banner"):
		hud._show_banner(txt, col, 1.1)

func _ground_y(x: float, z: float) -> float:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -10.0, z), 1)
	var hit: Dictionary = sp.intersect_ray(q)
	return hit.position.y if hit else 5.95
