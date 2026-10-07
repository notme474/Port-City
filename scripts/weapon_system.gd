extends Node3D
## 武器系统：抽象霓虹几何枪（手枪/步枪/霰弹）+ hitscan + 曳光/枪口焰/弹壳
## 挂在 Player 下；相机中心射线判定；伤害沿碰撞体父链找 take_damage/bullet_hit

signal ammo_changed(mag, reserve)
signal weapon_changed(index, wdata, unlocked_arr)
signal hit_confirmed(damage)
signal kill_confirmed(target_name)
signal shot_fired(wdata)

const RANGE := 300.0

var player: CharacterBody3D
var view: Node3D
var camera: Camera3D

var weapons: Array[WeaponData] = []
var unlocked: Array[bool] = [true, false, false]   # 手枪默认解锁，步枪/霰弹靠拾取
var mags: Array[int] = []
var reserves: Array[int] = []
var current := 0

var aiming := false
var alien_skin := false         ## 外星涂装（路灯外星人任务奖励）：紫身 + 毒绿霓虹
var _cool := 0.0
var _reloading := 0.0
var _fired_t := 9.9          # 距上次开火的时间（动画用）
var _bt_on := false

var _bone: BoneAttachment3D
var _gun: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	await get_tree().process_frame   # 等 player/view 就绪
	view = player.get("view")
	camera = view.get_node("Camera") if view else null
	_reg_actions()
	_build_arsenal()
	_attach_hand()
	_switch(0, true)


# ---------- 输入动作（运行时注册，不动 project.godot） ----------
func _reg_actions() -> void:
	_mouse_action("shoot", MOUSE_BUTTON_LEFT)
	_mouse_action("aim", MOUSE_BUTTON_RIGHT)
	_key_action("reload", KEY_R)
	_key_action("weapon_1", KEY_1)
	_key_action("weapon_2", KEY_2)
	_key_action("weapon_3", KEY_3)
	_key_action("bullet_time", KEY_V)

func _mouse_action(act: String, btn: MouseButton) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act)
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	InputMap.action_add_event(act, ev)

func _key_action(act: String, key: Key) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(act, ev)


# ---------- 武器库 ----------
func _build_arsenal() -> void:
	var p := WeaponData.new()
	p.id = "pistol"; p.display_name = "手枪"
	p.damage = 25.0; p.fire_interval = 0.28; p.mag_size = 12; p.max_reserve = 60
	p.spread_deg = 1.2; p.reload_time = 1.1; p.two_handed = false
	p.tracer_color = Color(0.35, 0.95, 1.0); p.gun_kind = "pistol"
	var r := WeaponData.new()
	r.id = "rifle"; r.display_name = "步枪"
	r.damage = 18.0; r.fire_interval = 0.1; r.mag_size = 30; r.max_reserve = 120
	r.spread_deg = 2.2; r.automatic = true; r.reload_time = 1.5; r.two_handed = true
	r.tracer_color = Color(1.0, 0.35, 0.8); r.gun_kind = "rifle"
	var s := WeaponData.new()
	s.id = "shotgun"; s.display_name = "霰弹枪"
	s.damage = 12.0; s.fire_interval = 0.85; s.mag_size = 6; s.max_reserve = 30
	s.pellets = 8; s.spread_deg = 7.0; s.reload_time = 1.8; s.two_handed = true
	s.tracer_color = Color(1.0, 0.85, 0.25); s.gun_kind = "shotgun"
	weapons = [p, r, s]
	for w in weapons:
		mags.append(w.mag_size)
		reserves.append(w.max_reserve / 2)


# ---------- 挂到右手武器骨 ----------
func _attach_hand() -> void:
	var skel := player.get_node("Character").find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		push_warning("WeaponSystem: 找不到 Skeleton3D，枪挂在玩家身上")
		_gun = Node3D.new()
		player.add_child(_gun)
		return
	_bone = BoneAttachment3D.new()
	_bone.bone_name = "handslot.r"
	skel.add_child(_bone)
	_gun = Node3D.new()
	# KayKit 瞄准姿势：handslot.r 的 X 轴指向身前，模型枪管沿 -Z，
	# 绕 Y 转 -90° 让 -Z 对准骨骼 +X（前方）
	_gun.rotation_degrees = Vector3(0, -90, 0)
	# Q 版角色手小，整体放大枪身让霓虹枪在第三人称下清晰可见
	_gun.scale = Vector3.ONE * 1.6
	_bone.add_child(_gun)
	# 枪口闪光
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	_flash.mesh = q
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 6.0
	add_child(_flash_light)


func _build_gun(w: WeaponData) -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_" + w.id
	var body_mat := StandardMaterial3D.new()
	var glow := StandardMaterial3D.new()
	if alien_skin:
		# 外星涂装：深紫金属机身 + 毒绿霓虹条
		body_mat.albedo_color = Color(0.16, 0.05, 0.28)
		body_mat.metallic = 0.85
		body_mat.roughness = 0.25
		body_mat.emission_enabled = true
		body_mat.emission = Color(0.15, 0.9, 0.4)
		body_mat.emission_energy_multiplier = 0.35
		glow.albedo_color = Color(0.35, 1.0, 0.45)
		glow.emission_enabled = true
		glow.emission = Color(0.35, 1.0, 0.45)
		glow.emission_energy_multiplier = 4.0
	else:
		body_mat.albedo_color = Color(0.13, 0.14, 0.17)
		body_mat.metallic = 0.7
		body_mat.roughness = 0.35
		glow.albedo_color = w.tracer_color
		glow.emission_enabled = true
		glow.emission = w.tracer_color
		glow.emission_energy_multiplier = 3.0

	var box := func(size: Vector3, pos: Vector3, mat: Material, rot_x := 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees.x = rot_x
		root.add_child(mi)
		return mi
	var cyl := func(r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r; cm.bottom_radius = r; cm.height = h
		mi.mesh = cm
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees.x = 90.0   # 圆柱 Y 轴 → Z 轴（枪管）
		root.add_child(mi)
		return mi

	var mz := Vector3.ZERO
	match w.gun_kind:
		"pistol":
			box.call(Vector3(0.07, 0.10, 0.24), Vector3(0, 0.02, -0.06), body_mat)
			cyl.call(0.026, 0.20, Vector3(0, 0.035, -0.22), body_mat)
			box.call(Vector3(0.06, 0.15, 0.08), Vector3(0, -0.075, 0.06), body_mat, 12.0)
			box.call(Vector3(0.075, 0.02, 0.10), Vector3(0, 0.045, -0.10), glow)   # 顶部霓虹条
			mz = Vector3(0, 0.035, -0.34)
		"rifle":
			box.call(Vector3(0.07, 0.12, 0.55), Vector3(0, 0.02, -0.10), body_mat)
			cyl.call(0.022, 0.50, Vector3(0, 0.045, -0.60), body_mat)
			box.call(Vector3(0.06, 0.11, 0.20), Vector3(0, 0.0, 0.26), body_mat, 8.0)   # 枪托
			box.call(Vector3(0.05, 0.16, 0.10), Vector3(0, -0.11, 0.0), body_mat, 10.0) # 弹匣
			cyl.call(0.03, 0.16, Vector3(0, 0.115, -0.05), body_mat)                    # 瞄准镜
			box.call(Vector3(0.075, 0.02, 0.30), Vector3(0, 0.05, -0.35), glow)
			mz = Vector3(0, 0.045, -0.86)
		"shotgun":
			box.call(Vector3(0.09, 0.13, 0.50), Vector3(0, 0.02, -0.06), body_mat)
			cyl.call(0.032, 0.48, Vector3(-0.036, 0.05, -0.48), body_mat)
			cyl.call(0.032, 0.48, Vector3(0.036, 0.05, -0.48), body_mat)
			box.call(Vector3(0.08, 0.06, 0.14), Vector3(0, -0.045, -0.28), body_mat)    # 泵动
			box.call(Vector3(0.07, 0.10, 0.20), Vector3(0, 0.0, 0.24), body_mat, 8.0)
			box.call(Vector3(0.10, 0.02, 0.24), Vector3(0, 0.09, -0.30), glow)
			mz = Vector3(0, 0.05, -0.74)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = mz
	root.add_child(_muzzle)
	return root


# ---------- 主循环 ----------
func _process(delta: float) -> void:
	if weapons.is_empty():
		return
	_cool = maxf(0.0, _cool - delta)
	_fired_t += delta
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()
	_poll_input()
	_update_anim()


func _poll_input() -> void:
	# 玩家死亡演出中禁止一切武器操作（开火/瞄准/切枪/子弹时间）
	var pl: Node = get_parent()
	if pl and pl.get("is_dead"):
		aiming = false
		return
	aiming = Input.is_action_pressed("aim")
	# 子弹时间（按住 V）
	if Input.is_action_just_pressed("bullet_time") and not _bt_on:
		_bt_on = true
		Engine.time_scale = 0.3
		get_tree().root.set_meta("bullet_time_scale", 0.3)
	elif Input.is_action_just_released("bullet_time") and _bt_on:
		_bt_on = false
		Engine.time_scale = 1.0
		get_tree().root.set_meta("bullet_time_scale", 1.0)
	# 切枪
	for i in range(3):
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			_switch(i)
	# 换弹
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	# 开火
	var w: WeaponData = weapons[current]
	if w.automatic:
		if Input.is_action_pressed("shoot"):
			_try_fire()
	elif Input.is_action_just_pressed("shoot"):
		_try_fire()


func _switch(i: int, force := false) -> void:
	if i == current and not force:
		return
	if i < 0 or i >= weapons.size() or not unlocked[i]:
		return
	current = i
	_reloading = 0.0
	# 重建枪模
	for c in _gun.get_children():
		c.queue_free()
	var g := _build_gun(weapons[current])
	# Q 版角色手小，整体放大枪身让霓虹枪在第三人称下清晰可见
	g.scale = Vector3.ONE * 3.0
	_gun.add_child(g)
	ammo_changed.emit(mags[current], reserves[current])
	weapon_changed.emit(current, weapons[current], unlocked)


func _start_reload() -> void:
	var w: WeaponData = weapons[current]
	if _reloading > 0.0 or mags[current] >= w.mag_size or reserves[current] <= 0:
		return
	_reloading = w.reload_time

func _finish_reload() -> void:
	var w: WeaponData = weapons[current]
	var need: int = w.mag_size - mags[current]
	var take: int = mini(need, reserves[current])
	mags[current] += take
	reserves[current] -= take
	ammo_changed.emit(mags[current], reserves[current])


func _try_fire() -> void:
	if _cool > 0.0 or _reloading > 0.0 or camera == null:
		return
	if mags[current] <= 0:
		_start_reload()
		return
	var w: WeaponData = weapons[current]
	mags[current] -= 1
	_cool = w.fire_interval
	_fired_t = 0.0
	ammo_changed.emit(mags[current], reserves[current])
	# 镜头后坐
	if view:
		view.camera_rotation += Vector3(0.35 if w.gun_kind != "shotgun" else 1.0, randf_range(-0.15, 0.15), 0)
	_muzzle_flash(w)
	_eject_shell(w)
	shot_fired.emit(w)
	for i in range(w.pellets):
		_fire_ray(w)


func _fire_ray(w: WeaponData) -> void:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	# 圆锥扩散
	var rad := deg_to_rad(w.spread_deg)
	var a := randf() * TAU
	var rr := rad * sqrt(randf())
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	dir = (dir + right * tan(rr) * cos(a) + up * tan(rr) * sin(a)).normalized()

	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
	q.collision_mask = 3                 # 1=场景/角色 2=可打目标 Area
	q.collide_with_areas = true
	q.exclude = [player]
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	var end: Vector3 = hit.get("position", origin + dir * RANGE)
	_spawn_tracer(w, _muzzle_global(), end)
	if hit.is_empty():
		return
	_spawn_impact(end, w.tracer_color)
	var target := _resolve_target(hit.collider)
	if target == null:
		return
	var died := false
	var tname := str(target.name)
	if target.has_method("bullet_hit"):
		died = bool(target.bullet_hit(w.damage))
	else:
		target.take_damage(w.damage)
		var hpv = target.get("hp")
		died = hpv != null and float(hpv) <= 0.0
		tname = str(target.get("display_name")) if target.get("display_name") != null else tname
	_spawn_damage_label(end, w.damage, w.tracer_color, died)
	hit_confirmed.emit(w.damage)
	if died:
		KillFx.explode(get_tree(), end + Vector3(0, 0.5, 0), w.tracer_color)
		KillFx.hitstop(get_tree())
		kill_confirmed.emit(tname)

## 3D 伤害飘字：弹起、上升、淡出
func _spawn_damage_label(pos: Vector3, dmg: float, color: Color, crit: bool) -> void:
	var l := Label3D.new()
	l.text = ("%d!" if crit else "%d") % int(dmg)
	l.font_size = 96 if crit else 64
	l.modulate = Color.WHITE if crit else color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	l.outline_modulate = Color.BLACK
	l.outline_render_priority = 1
	l.outline_size = 14
	get_tree().root.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.6, randf_range(-0.2, 0.2))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.4, 0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


## 沿碰撞体父链找可受伤害节点
func _resolve_target(collider: Object) -> Node:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 5:
		if n == player:
			return null
		if n.has_method("take_damage") or n.has_method("bullet_hit"):
			return n
		n = n.get_parent()
		depth += 1
	return null


func _muzzle_global() -> Vector3:
	if _muzzle and is_instance_valid(_muzzle):
		return _muzzle.global_position
	return camera.global_position - camera.global_transform.basis.z * 2.0


# ---------- 特效 ----------
func _muzzle_flash(w: WeaponData) -> void:
	_flash.visible = true
	_flash.global_position = _muzzle_global()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = w.tracer_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.material_override = mat
	_flash.rotation.z = randf() * TAU
	_flash_light.light_color = w.tracer_color
	_flash_light.light_energy = 4.0
	_flash_light.global_position = _muzzle_global()
	var tw := create_tween()
	tw.tween_property(_flash_light, "light_energy", 0.0, 0.07)
	tw.tween_callback(func(): _flash.visible = false)

func _spawn_tracer(w: WeaponData, from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, len)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(w.tracer_color, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	get_tree().root.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)

func _spawn_impact(pos: Vector3, color: Color) -> void:
	for i in range(5):
		var sp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.07
		sp.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		sp.material_override = mat
		get_tree().root.add_child(sp)
		sp.global_position = pos
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
		var tw := sp.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "global_position", pos + dir * randf_range(0.5, 1.2), 0.25)
		tw.tween_property(sp, "scale", Vector3.ZERO, 0.28)
		tw.chain().tween_callback(sp.queue_free)

func _eject_shell(w: WeaponData) -> void:
	var sh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.06)
	sh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	mat.metallic = 0.8
	mat.roughness = 0.3
	sh.material_override = mat
	get_tree().root.add_child(sh)
	var start := _muzzle_global() + Vector3(0, -0.05, 0)
	sh.global_position = start
	var side := camera.global_transform.basis.x if camera else Vector3.RIGHT
	var tw := sh.create_tween()
	tw.tween_property(sh, "global_position", start + side * 0.5 + Vector3(0, 0.35, 0), 0.12)
	tw.tween_property(sh, "global_position", start + side * 0.8 + Vector3(0, -1.2, 0), 0.4)
	tw.tween_callback(sh.queue_free)


# ---------- 动画（写 player.anim_locked，由 player.gd 播放） ----------
func _update_anim() -> void:
	if player == null or not ("anim_locked" in player):
		return
	var w: WeaponData = weapons[current]
	var pre := "2H_Ranged_" if w.two_handed else "1H_Ranged_"
	var lock := ""
	if _reloading > 0.0:
		lock = pre + "Reload"
	elif _fired_t < 0.18 and w.automatic:
		lock = pre + "Shooting"
	elif _fired_t < 0.18:
		lock = pre + "Shoot"
	elif aiming:
		lock = pre + "Aiming"
	player.anim_locked = lock
	player.aim_facing = aiming or _fired_t < 0.18


# ---------- 拾取接口 ----------
func unlock_weapon(id: String) -> bool:
	for i in range(weapons.size()):
		if weapons[i].id == id:
			if unlocked[i]:
				return false
			unlocked[i] = true
			reserves[i] = weapons[i].max_reserve
			_switch(i, true)
			weapon_changed.emit(current, weapons[current], unlocked)
			return true
	return false

func add_ammo_all(frac: float) -> void:
	for i in range(weapons.size()):
		if unlocked[i]:
			reserves[i] = mini(weapons[i].max_reserve, reserves[i] + int(weapons[i].max_reserve * frac))
	ammo_changed.emit(mags[current], reserves[current])
