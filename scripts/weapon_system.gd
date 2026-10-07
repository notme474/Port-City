extends Node3D
## 武器系统：抽象霓虹几何枪（手枪/步枪/霰弹）
## 相机中心瞄准；hitscan 或抛射物（带弹道下坠）；射线+近距离形状双重命中验证；
## 距离衰减/部位倍率；曳光/枪口焰/弹壳/弹孔/3D 伤害飘字/可恢复后坐力/屏幕震动；
## 第一人称时枪挂到相机锚点，第三人称挂右手骨骼。

signal ammo_changed(mag, reserve)
signal weapon_changed(index, wdata, unlocked_arr)
signal hit_confirmed(damage)
signal kill_confirmed(target_name)
signal shot_fired(wdata)

const RANGE := 300.0
const PROJ_GRAV := 1.4        ## 弹丸基础重力（街机感轻微下坠）
const MAX_HOLES := 24         ## 场景中同时存在的弹孔上限
const Sfx = preload("res://scripts/sfx.gd")

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
var _equip_t := 0.0             ## 切枪后开火锁定剩余秒（要求 <=0.3s）
var _reloading := 0.0
var _fired_t := 9.9          # 距上次开火的时间（动画用）
var _bt_on := false

var _bone: BoneAttachment3D
var _gun: Node3D
var _fp_holder: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D

# 抛射物：Array[Dictionary]
var _projs: Array[Dictionary] = []
# 弹孔贴花
var _holes: Array[MeshInstance3D] = []
# 瞄准预测线
var _predict_mi: MeshInstance3D
var _predict_imm: ImmediateMesh
var _predict_mat: StandardMaterial3D
var _predict_dot: MeshInstance3D


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	await get_tree().process_frame   # 等 player/view 就绪
	view = player.get("view")
	camera = view.get_node("Camera") if view else null
	_reg_actions()
	_build_arsenal()
	_attach_hand()
	_create_fp_holder()
	_create_prediction()
	if view and view.has_signal("view_mode_changed"):
		view.view_mode_changed.connect(_on_view_mode)
	_switch(0, true)
	if view:
		_on_view_mode(view.first_person)


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
	p.bullet_speed = 260.0; p.falloff_range = 60.0; p.falloff_min = 0.5
	p.recoil_pitch = 2.2; p.recoil_yaw = 0.6; p.shake = 0.018
	var r := WeaponData.new()
	r.id = "rifle"; r.display_name = "步枪"
	r.damage = 18.0; r.fire_interval = 0.1; r.mag_size = 30; r.max_reserve = 120
	r.spread_deg = 2.2; r.automatic = true; r.reload_time = 1.5; r.two_handed = true
	r.tracer_color = Color(1.0, 0.35, 0.8); r.gun_kind = "rifle"
	r.bullet_speed = 420.0; r.falloff_range = 120.0; r.falloff_min = 0.7
	r.recoil_pitch = 1.4; r.recoil_yaw = 0.4; r.shake = 0.012
	var s := WeaponData.new()
	s.id = "shotgun"; s.display_name = "霰弹枪"
	s.damage = 12.0; s.fire_interval = 0.85; s.mag_size = 6; s.max_reserve = 30
	s.pellets = 8; s.spread_deg = 7.0; s.reload_time = 1.8; s.two_handed = true
	s.tracer_color = Color(1.0, 0.85, 0.25); s.gun_kind = "shotgun"
	s.bullet_speed = 200.0; s.falloff_range = 30.0; s.falloff_min = 0.25
	s.recoil_pitch = 4.5; s.recoil_yaw = 1.1; s.shake = 0.05
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

## 第一人称枪锚点：挂在相机右下前方
func _create_fp_holder() -> void:
	if camera == null:
		return
	_fp_holder = Node3D.new()
	_fp_holder.name = "FPWeaponHolder"
	_fp_holder.position = Vector3(0.24, -0.22, -0.45)
	_fp_holder.scale = Vector3.ONE * 0.2
	camera.add_child(_fp_holder)

## 视角切换：枪在骨骼与相机锚点之间重新挂载（身体隐藏后第一人称仍能看到武器）
func _on_view_mode(fp: bool) -> void:
	if _gun == null:
		return
	if fp and _fp_holder:
		_gun.reparent(_fp_holder, false)
		_gun.transform = Transform3D.IDENTITY
	else:
		if _bone:
			_gun.reparent(_bone, false)
			_gun.rotation_degrees = Vector3(0, -90, 0)
			_gun.scale = Vector3.ONE * 1.6


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
	_equip_t = maxf(0.0, _equip_t - delta)
	_fired_t += delta
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()
	_poll_input()
	_update_anim()
	_update_prediction()

func _physics_process(delta: float) -> void:
	_simulate_projectiles(delta)


func _poll_input() -> void:
	# 玩家死亡演出 / 商店面板 / 驾驶中禁止武器操作
	var pl: Node = get_parent()
	var locked: bool = pl != null and bool(pl.get("is_dead"))
	locked = locked or (pl != null and bool(pl.get("input_locked")))
	locked = locked or (view != null and view.chase != null)
	if locked:
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
	# 切枪后短暂锁定开火（<=0.3s），营造切换重量感
	_equip_t = weapons[current].switch_time
	ammo_changed.emit(mags[current], reserves[current])
	weapon_changed.emit(current, weapons[current], unlocked)


func _start_reload() -> void:
	var w: WeaponData = weapons[current]
	if _reloading > 0.0 or mags[current] >= w.mag_size or reserves[current] <= 0:
		return
	_reloading = w.reload_time
	Sfx.play_3d(player, _muzzle_global(), "click", -10.0)

func _finish_reload() -> void:
	var w: WeaponData = weapons[current]
	var need: int = w.mag_size - mags[current]
	var take: int = mini(need, reserves[current])
	mags[current] += take
	reserves[current] -= take
	ammo_changed.emit(mags[current], reserves[current])


func _try_fire() -> void:
	if _cool > 0.0 or _reloading > 0.0 or _equip_t > 0.0 or camera == null:
		return
	if mags[current] <= 0:
		Sfx.play_3d(player, _muzzle_global(), "click", -8.0)
		_start_reload()
		return
	var w: WeaponData = weapons[current]
	mags[current] -= 1
	_cool = w.fire_interval
	_fired_t = 0.0
	ammo_changed.emit(mags[current], reserves[current])
	# 可恢复镜头后坐 + 屏幕震动（替代旧版永久累积视角的写法）
	if view:
		view.add_recoil(w.recoil_pitch, randf_range(-w.recoil_yaw, w.recoil_yaw))
		view.add_shake(w.shake)
	# 开火同帧播放枪声（3D 空间音）
	Sfx.play_3d(player, _muzzle_global(), w.gun_kind, -4.0 if w.gun_kind != "shotgun" else -1.0)
	_muzzle_flash(w)
	_eject_shell(w)
	shot_fired.emit(w)
	for i in range(w.pellets):
		_fire_pellet(w)


# ---------- 弹丸发射：hitscan 或抛射物 ----------
func _fire_pellet(w: WeaponData) -> void:
	var dir := _spread_dir(-camera.global_transform.basis.z, w.spread_deg)
	if w.bullet_speed > 0.0:
		# 从枪口发射、向准星方向收敛
		var mz := _muzzle_global()
		var aim_pt: Vector3 = camera.global_position + dir * 50.0
		var pdir: Vector3 = (aim_pt - mz).normalized()
		_spawn_projectile(w, mz, pdir)
		return
	var origin := camera.global_position
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
	_apply_hit(hit, w, origin.distance_to(end), dir)

## 圆锥扩散（基于相机朝向）
func _spread_dir(base: Vector3, spread_deg: float) -> Vector3:
	var rad := deg_to_rad(spread_deg)
	var a := randf() * TAU
	var rr := rad * sqrt(randf())
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	return (base + right * tan(rr) * cos(a) + up * tan(rr) * sin(a)).normalized()


# ---------- 抛射物（弹道下坠 + 射线步进命中） ----------
func _spawn_projectile(w: WeaponData, start: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 1.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(w.tracer_color, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mi.material_override = mat
	get_tree().root.add_child(mi)
	mi.global_position = start
	var pd: Dictionary = {
		"start": start, "pos": start,
		"vel": dir * w.bullet_speed,
		"traveled": 0.0, "life": 0.0,
		"w": w, "mesh": mi, "mat": mat,
	}
	_projs.append(pd)

func _simulate_projectiles(delta: float) -> void:
	if _projs.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var step_dt: float = delta / 2.0
	var alive: Array[Dictionary] = []
	for pd in _projs:
		var w: WeaponData = pd["w"]
		var pos: Vector3 = pd["pos"]
		var vel: Vector3 = pd["vel"]
		var traveled: float = pd["traveled"]
		var dead := false
		for _step in 2:
			vel.y -= PROJ_GRAV * w.gravity_scale * step_dt
			var nxt: Vector3 = pos + vel * step_dt
			var seg: float = pos.distance_to(nxt)
			var q := PhysicsRayQueryParameters3D.create(pos, nxt, 3)
			q.collide_with_areas = true
			q.exclude = [player]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var end: Vector3 = hit.position
				traveled += pos.distance_to(end)
				_spawn_impact(end, w.tracer_color)
				_apply_hit(hit, w, traveled, vel.normalized())
				dead = true
				break
			pos = nxt
			traveled += seg
		pd["life"] = float(pd["life"]) + delta
		var mi: MeshInstance3D = pd["mesh"]
		if dead or traveled >= RANGE or pos.y < -10.0 or float(pd["life"]) > 3.0:
			if is_instance_valid(mi):
				mi.queue_free()
			continue
		pd["pos"] = pos
		pd["vel"] = vel
		pd["traveled"] = traveled
		# 束状曳光：从枪口到当前位置，随生命快速淡出
		if is_instance_valid(mi):
			var st: Vector3 = pd["start"]
			var ln: float = maxf(st.distance_to(pos), 0.1)
			(mi.mesh as BoxMesh).size = Vector3(0.025, 0.025, ln)
			mi.global_position = (st + pos) * 0.5
			mi.look_at(pos, Vector3.UP)
			(pd["mat"] as StandardMaterial3D).albedo_color.a = 0.9 * exp(-float(pd["life"]) * 7.0)
		alive.append(pd)
	_projs = alive


# ---------- 命中结算：距离衰减 + 部位倍率 + 射线/形状双重验证 ----------
func _apply_hit(hit: Dictionary, w: WeaponData, dist: float, dir: Vector3) -> void:
	var end: Vector3 = hit.position
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var target: Node = _resolve_target(hit.collider)
	# 双重验证：在撞击点前 12cm 放一个 0.22m 球形形状查询，
	# 射线擦边漏掉的薄目标/Area 由形状查询兜底命中
	if target == null:
		var s2: Node = _shape_target(end - dir * 0.12)
		if s2 != null:
			target = s2
	if target == null:
		# 纯环境命中：只留弹孔
		_spawn_hole(end, normal)
		return
	var head: bool = _is_head(hit.collider)
	var mult: float = _falloff(w, dist) * (1.6 if head else _part_multiplier(hit.collider))
	var dmg: float = w.damage * mult
	var died := false
	var tname := str(target.name)
	if target.has_method("bullet_hit"):
		died = bool(target.bullet_hit(dmg))
	else:
		target.take_damage(dmg)
		var hpv = target.get("hp")
		died = hpv != null and float(hpv) <= 0.0
		tname = str(target.get("display_name")) if target.get("display_name") != null else tname
	_spawn_damage_label(end, dmg, w.tracer_color, died, mult)
	hit_confirmed.emit(dmg)
	if head:
		# WeaponSystem 是 Player 的子节点，StatsSystem 与 Player 同属主场景根
		var ss: Node = null
		if player:
			ss = player.get_parent().get_node_or_null("StatsSystem")
		if ss == null and get_tree().current_scene:
			ss = get_tree().current_scene.get_node_or_null("StatsSystem")
		if ss and ss.has_method("add_stat"):
			ss.add_stat("headshots", 1.0)
	if died:
		KillFx.explode(get_tree(), end + Vector3(0, 0.5, 0), w.tracer_color)
		KillFx.hitstop(get_tree())
		kill_confirmed.emit(tname)

func _falloff(w: WeaponData, dist: float) -> float:
	var t: float = clampf(dist / maxf(w.falloff_range, 0.01), 0.0, 1.0)
	return lerpf(1.0, w.falloff_min, t)

## 部位倍率：按碰撞体/父节点名识别（后续高模带 head/spine/leg 碰撞盒即自动生效）
func _part_multiplier(collider: Object) -> float:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 3:
		var nm: String = n.name.to_lower()
		if "head" in nm:
			return 1.6
		if "leg" in nm or "arm" in nm:
			return 0.7
		n = n.get_parent()
		depth += 1
	return 1.0

## 是否命中头部命中区（沿父链 3 跳内节点名含 head）
func _is_head(collider: Object) -> bool:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 3:
		if "head" in n.name.to_lower():
			return true
		n = n.get_parent()
		depth += 1
	return false

func _shape_target(center: Vector3) -> Node:
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	params.shape = sph
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 3
	params.collide_with_areas = true
	params.exclude = [player]
	var arr: Array = get_world_3d().direct_space_state.intersect_shape(params, 8)
	for r in arr:
		var t: Node = _resolve_target(r.collider)
		if t != null:
			return t
	return null

## 3D 伤害飘字：弹起、上升、淡出；倍率偏离 1.0 时显示部位/距离提示色
func _spawn_damage_label(pos: Vector3, dmg: float, color: Color, crit: bool, mult: float = 1.0) -> void:
	var l := Label3D.new()
	l.text = ("%d!" if crit else "%d") % int(round(dmg))
	l.font_size = 96 if crit else 64
	l.modulate = Color.WHITE if crit else color
	if mult >= 1.5:
		l.modulate = Color(1.0, 0.85, 0.3)
	elif mult <= 0.75:
		l.modulate = Color(0.7, 0.8, 1.0)
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

## 弹孔贴花：面向法线的暗色四边形，6 秒后淡出，超出上限顶替最老的
func _spawn_hole(pos: Vector3, normal: Vector3) -> void:
	while _holes.size() >= MAX_HOLES:
		var old: MeshInstance3D = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	q.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.02, 0.02, 0.03, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material_override = mat
	get_tree().root.add_child(q)
	q.global_position = pos + normal * 0.015
	# QuadMesh 正面朝 -Z，看向 normal 方向即朝外
	q.look_at(pos + normal, Vector3.UP)
	q.rotate_object_local(Vector3(0, 0, 1), randf() * TAU)
	q.scale = Vector3.ONE * 0.3
	var tw := q.create_tween()
	tw.tween_property(q, "scale", Vector3.ONE, 0.06).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(5.2)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(func():
		if is_instance_valid(q):
			_holes.erase(q)
			q.queue_free())
	_holes.append(q)

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


# ---------- 瞄准弹道预测线 ----------
func _create_prediction() -> void:
	_predict_imm = ImmediateMesh.new()
	_predict_mi = MeshInstance3D.new()
	_predict_mi.mesh = _predict_imm
	_predict_mat = StandardMaterial3D.new()
	_predict_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_predict_mat.albedo_color = Color(0.45, 1.0, 0.9, 0.4)
	_predict_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_predict_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_predict_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(_predict_mi)
	_predict_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045; sm.height = 0.09
	_predict_dot.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.4, 0.8, 0.85)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.4, 0.8)
	dm.emission_energy_multiplier = 2.0
	_predict_dot.material_override = dm
	_predict_dot.visible = false
	get_tree().root.add_child(_predict_dot)

func _update_prediction() -> void:
	_predict_imm.clear_surfaces()
	var show: bool = aiming and camera != null and _equip_t <= 0.0 \
			and _reloading <= 0.0 and mags[current] > 0
	if not show:
		_predict_mi.visible = false
		_predict_dot.visible = false
		return
	var w: WeaponData = weapons[current]
	var start: Vector3 = _muzzle_global()
	var cam_dir: Vector3 = -camera.global_transform.basis.z
	var aim_pt: Vector3 = camera.global_position + cam_dir * 50.0
	var dir: Vector3 = (aim_pt - start).normalized()
	var pts := PackedVector3Array()
	pts.append(start)
	var space := get_world_3d().direct_space_state
	var end_pt := start + dir * 120.0
	if w.bullet_speed > 0.0:
		# 抛射物：按真实重力分步采样，并在撞到表面时截断
		var p := start
		var v: Vector3 = dir * w.bullet_speed
		var h := 0.03
		for i in 26:
			v.y -= PROJ_GRAV * w.gravity_scale * h
			var np2: Vector3 = p + v * h
			var q := PhysicsRayQueryParameters3D.create(p, np2, 3)
			q.collide_with_areas = true
			q.exclude = [player]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				pts.append(hit.position)
				end_pt = hit.position
				break
			p = np2
			pts.append(p)
	else:
		var q := PhysicsRayQueryParameters3D.create(start, start + dir * 120.0, 3)
		q.collide_with_areas = true
		q.exclude = [player]
		var hit2 := space.intersect_ray(q)
		if not hit2.is_empty():
			end_pt = hit2.position
		pts.append(end_pt)
	_predict_imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _predict_mat)
	for pt in pts:
		_predict_imm.surface_add_vertex(pt)
	_predict_imm.surface_end()
	_predict_mi.visible = true
	_predict_dot.visible = true
	_predict_dot.global_position = end_pt
	var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.25
	_predict_dot.scale = Vector3.ONE * pulse


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
