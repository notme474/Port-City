extends Node3D
## 恐龙：带 HP + 悬浮血条，被车/玩家撞击掉血，归零倒下消失

@export var max_hp := 100.0
var hp := 100.0

var _bar: Sprite3D
var _hit_area: Area3D
var _dead := false
var _sink_t := 0.0

func _ready() -> void:
	hp = max_hp
	_build_healthbar()
	_build_hit_area()

func _build_healthbar() -> void:
	# 用 Sprite3D + 程序纹理画血条（无需外部图片）
	_bar = Sprite3D.new()
	_bar.name = "HP"
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.position = Vector3(0, 7.5, 0)
	_bar.pixel_size = 0.02
	add_child(_bar)
	_update_bar()

func _update_bar() -> void:
	var w := 120
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.7))
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var fw := int(w * frac)
	var col := Color(0.2, 0.9, 0.3) if frac > 0.4 else Color(0.95, 0.25, 0.2)
	for x in range(fw):
		for y in range(2, h - 2):
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_bar.texture = tex

func _build_hit_area() -> void:
	_hit_area = Area3D.new()
	_hit_area.name = "HitArea"
	_hit_area.collision_layer = 2   # 武器射线 mask=3 可命中
	_hit_area.collision_mask = 1
	add_child(_hit_area)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.5, 6, 9)
	cs.shape = sh
	cs.position = Vector3(0, 3, 0)
	_hit_area.add_child(cs)
	_hit_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _dead:
		return
	# 车或玩家撞入：按对方速度掉血
	var impact := 25.0
	if body is CharacterBody3D:
		var v: Vector3 = body.velocity
		var sp := Vector2(v.x, v.z).length()
		impact = clampf(sp * 2.0, 10.0, 60.0)
		# 车撞恐龙，车也会受反冲
	take_damage(impact)

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	_update_bar()
	# 受击抖动
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", 0.15, 0.06)
	tw.tween_property(self, "rotation:z", -0.1, 0.06)
	tw.tween_property(self, "rotation:z", 0.0, 0.08)
	if hp <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	# 倒下
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation:x", deg_to_rad(88), 0.6).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(_bar, "modulate:a", 0.0, 0.4)
	# 1.5 秒后下沉消失
	await get_tree().create_timer(1.5).timeout
	var tw2 := create_tween()
	tw2.tween_property(self, "position:y", position.y - 8.0, 1.2)
	await tw2.finished
	queue_free()
