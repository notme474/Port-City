extends Node3D
## 抽象靶场：码头甲板静态靶 ×6 + 市中心上空盘旋靶 ×3
## 靶子是 StaticBody3D（layer 1），带 hp/take_damage，可被武器射线命中

class Target extends StaticBody3D:
	var hp := 60.0
	var max_hp := 60.0
	var display_name := "训练靶"
	var _mi: MeshInstance3D
	var _mat: StandardMaterial3D
	var _color: Color
	var _dead := false

	func setup(color: Color, display: String) -> void:
		_color = color
		display_name = display
		collision_layer = 1
		collision_mask = 0
		# 外环（圆环）+ 内芯（方块），纯几何抽象
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.7
		ring.mesh = tm
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = color
		_mat.emission_enabled = true
		_mat.emission = color
		_mat.emission_energy_multiplier = 1.5
		ring.material_override = _mat
		add_child(ring)
		_mi = ring
		var core := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.5
		core.mesh = bm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.1, 0.1, 0.12)
		core.material_override = cm
		add_child(core)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.75
		sh.height = 0.3
		cs.shape = sh
		cs.rotation_degrees.x = 90
		add_child(cs)

	func take_damage(amount: float) -> void:
		if _dead:
			return
		hp = maxf(0.0, hp - amount)
		# 受击闪白
		_mat.emission = Color.WHITE
		var tw := create_tween()
		tw.tween_property(_mat, "emission", _color, 0.2)
		if hp <= 0.0:
			_die()

	func _die() -> void:
		_dead = true
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "rotation_degrees:x", -80.0, 0.3)
		tw.tween_property(self, "scale", Vector3.ONE * 0.6, 0.3)
		await tw.finished
		await get_tree().create_timer(2.5).timeout
		# 复活
		hp = max_hp
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(self, "rotation_degrees:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK)
		tw2.tween_property(self, "scale", Vector3.ONE, 0.4)
		await tw2.finished
		_dead = false


const DOCK_ROW_Z := 408.0
var _pivot: Node3D   # 盘旋靶的旋转中心


func _ready() -> void:
	_build_dock_range()
	_build_drones()

## 码头甲板一排 6 个静态靶（甲板顶面世界 y=-0.2）
func _build_dock_range() -> void:
	var colors := [Color(0.3, 0.9, 1.0), Color(1.0, 0.4, 0.8), Color(1.0, 0.85, 0.25)]
	for i in range(6):
		var t := Target.new()
		t.name = "训练靶%d" % (i + 1)
		t.setup(colors[i % 3], "训练靶")
		t.position = Vector3(720.0 + i * 8.0, 1.2, DOCK_ROW_Z)
		add_child(t)
		# 靶座
		var stand := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 1.4, 0.15)
		stand.mesh = bm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.2, 0.22)
		stand.material_override = sm
		stand.position = Vector3(720.0 + i * 8.0, 0.5, DOCK_ROW_Z)
		add_child(stand)

## 市中心上空 3 个盘旋靶（绕 (60,10,-20) 半径 15）
func _build_drones() -> void:
	_pivot = Node3D.new()
	_pivot.name = "盘旋靶轴"
	_pivot.position = Vector3(60, 11, -20)
	add_child(_pivot)
	for i in range(3):
		var t := Target.new()
		t.name = "盘旋靶%d" % (i + 1)
		t.setup(Color(0.5, 1.0, 0.4), "盘旋靶")
		var a := TAU * i / 3.0
		t.position = Vector3(cos(a) * 15.0, sin(a * 2.0) * 1.5, sin(a) * 15.0)
		t.rotation_degrees.y = 90
		_pivot.add_child(t)

func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotation.y += delta * 0.5
