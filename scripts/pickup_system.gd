extends Node3D
## 拾取系统：发光悬浮旋转体——步枪/霰弹枪解锁 + 弹药包
## 步枪在恐龙岛桥头、霰弹枪在码头东端、弹药包散布四处

class Pickup extends Area3D:
	var kind := "ammo"          # rifle / shotgun / ammo
	var _base_y := 0.0
	var _t := 0.0

	func setup(p_kind: String, color: Color) -> void:
		kind = p_kind
		collision_layer = 0
		collision_mask = 1
		monitoring = true
		# 核心：发光八面体
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.6, 0.9, 0.6)
		mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.5
		mi.material_override = mat
		add_child(mi)
		# 底部光环
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.7
		ring.mesh = tm
		ring.rotation_degrees.x = 90
		ring.position.y = -0.6
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(color, 0.6)
		rm.emission_enabled = true
		rm.emission = color
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = rm
		add_child(ring)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.2
		cs.shape = sh
		add_child(cs)
		body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		_t += delta
		rotation.y += delta * 1.5
		position.y = _base_y + sin(_t * 2.0) * 0.15

	func _on_body(body: Node) -> void:
		if not body.is_in_group("player"):
			return
		var ws := body.get_node_or_null("WeaponSystem")
		if ws == null:
			return
		match kind:
			"rifle":
				if not ws.unlock_weapon("rifle"):
					return
				_toast(body, "拾取【步枪】！按 2 切换")
			"shotgun":
				if not ws.unlock_weapon("shotgun"):
					return
				_toast(body, "拾取【霰弹枪】！按 3 切换")
			"ammo":
				ws.add_ammo_all(0.5)
				_toast(body, "弹药 +50%")
		queue_free()

	func _toast(body: Node, text: String) -> void:
		var qs := body.get_tree().root.find_child("QuestSystem", true, false)
		if qs and qs.has_method("_msg"):
			qs._msg(text)


func _ready() -> void:
	_spawn("rifle", Vector3(-950, 7.6, -650), Color(1.0, 0.35, 0.8))    # 恐龙岛桥头
	_spawn("shotgun", Vector3(760, 0.6, 440), Color(1.0, 0.85, 0.25))     # 码头东端
	_spawn("ammo", Vector3(745, 0.6, 415), Color(0.4, 1.0, 0.5))          # 码头靶场
	_spawn("ammo", Vector3(100, 6.8, -40), Color(0.4, 1.0, 0.5))          # 市中心
	_spawn("ammo", Vector3(-240, 6.8, 120), Color(0.4, 1.0, 0.5))         # 中央公园
	_spawn("ammo", Vector3(-1000, 7.6, -700), Color(0.4, 1.0, 0.5))       # 恐龙岛腹地

func _spawn(kind: String, pos: Vector3, color: Color) -> void:
	var p := Pickup.new()
	p.name = "拾取_" + kind
	p.position = pos
	p.setup(kind, color)
	p._base_y = pos.y
	add_child(p)
