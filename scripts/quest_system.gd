extends Node3D
## 任务系统：老奶奶找猫(咪咪=机甲猫) → 虐待动物罚款1000 → 红眼追杀200秒
## 金币 = player.coins；标记走 Minimap；挂到 main.tscn 根

const M := "res://models/"
const GRANNY_POS := Vector3(120, 5.95, -60)   # 主城地面 y=5.95
const CAT_POS := Vector3(150, 5.95, -90)      # 老奶奶南边路口（约 40m，跑几步就到）
const POLICE_STATION := Vector3(300, 5.95, 200)
const FIGHT_R := 14.0
const CHASE_TIME := 200.0

enum Stage { IDLE, FIND_CAT, FIGHT, FINE, CHASE, DONE }
var stage := Stage.IDLE

var player: CharacterBody3D
var minimap: CanvasLayer
var hud_msg: Label
var coin_lbl: Label
var granny: Node3D
var _granny_spawn := GRANNY_POS   # 实际落点（贴合地面后的坐标）
var mechcat: Node3D
var _mech_mdl: Node3D
var _mech_light: OmniLight3D
var _mech_base_y := 0.0
var _mech_punch := 0.0
var _anim_t := 0.0
var mechcat_hp := 5
var chase_t := 0.0
var chase_speed := 7.5

const GRANNY_HIDE := ["Mage_Hat", "1H_Wand", "2H_Staff", "Spellbook", "Spellbook_open"]

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	player = get_tree().get_first_node_in_group("player")
	minimap = get_parent().get_node_or_null("Minimap")
	_build_ui()
	# 老奶奶落点贴合实际地面（探针实测该处人行道 y=7.35，常量 5.95 会陷进地里 1.4m）
	_granny_spawn = Vector3(GRANNY_POS.x,
		_ground_y(GRANNY_POS.x, GRANNY_POS.z, GRANNY_POS.y), GRANNY_POS.z)
	_spawn_granny()
	_spawn_mechcat()
	_spawn_police_station()
	if minimap:
		minimap.add_marker("granny", _granny_spawn, Color.YELLOW, "老奶奶")
	_msg("街上有个老奶奶（黄点），走进她脚下的黄色光圈就能接任务")

## 从高处向下射线取地面高度（取不到时用 fallback）
func _ground_y(x: float, z: float, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -40.0, z))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return (hit.position as Vector3).y

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	hud_msg = Label.new()
	hud_msg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud_msg.position = Vector2(0, 12)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.add_theme_font_size_override("font_size", 28)
	hud_msg.add_theme_color_override("font_color", Color.WHITE)
	hud_msg.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(hud_msg)

func _msg(t: String) -> void:
	if hud_msg: hud_msg.text = t

func _refresh_coins() -> void:
	# 金币显示由 hud.gd 的 Coins Label 负责，这里只触发刷新
	if player:
		player.coin_collected.emit(player.coins)

# ---------- NPC ----------
func _spawn_granny() -> void:
	granny = Node3D.new()
	granny.name = "老奶奶"
	granny.position = _granny_spawn
	add_child(granny)
	# KayKit 法师改造为老奶奶：原始模型含尖顶帽高达 3.0m，
	# 隐藏帽子/法杖/法术书后身高约 2.2m，×0.72 ≈ 1.58m（符合老人身高规格）
	var sc: PackedScene = load(M + "kaykit/Mage.glb")
	if sc:
		var mdl: Node3D = sc.instantiate()
		for nm in GRANNY_HIDE:
			var hider: Node = mdl.find_child(nm, true, false)
			if hider:
				hider.visible = false
		ModelUtil.snap_to_ground(mdl, 0.72)
		granny.add_child(mdl)
		_play_npc_anim(mdl, "Idle")
	# 与视觉匹配的碰撞胶囊（layer 1，玩家 mask 命中，不会再穿模）
	var body := StaticBody3D.new()
	body.name = "GrannyCollider"
	body.collision_layer = 1
	body.collision_mask = 0
	var gcs := CollisionShape3D.new()
	var gcap := CapsuleShape3D.new()
	gcap.radius = 0.35
	gcap.height = 1.4
	gcs.shape = gcap
	gcs.position.y = 0.7
	body.add_child(gcs)
	granny.add_child(body)
	# GTA 式黄色任务光圈：走进圈即接任务
	_spawn_quest_marker(_granny_spawn, "帮老奶奶找猫")

func _spawn_quest_marker(pos: Vector3, title: String) -> void:
	var mk: Node = Node3D.new()
	mk.set_script(load("res://scripts/quest_marker.gd"))
	add_child(mk)
	mk.setup(pos, Color(1.0, 0.85, 0.25), title)
	mk.connect("triggered", Callable(self, "_accept_quest"))

func _spawn_mechcat() -> void:
	mechcat = Node3D.new()
	mechcat.name = "机甲猫咪咪"
	mechcat.position = CAT_POS
	mechcat.visible = false
	add_child(mechcat)
	var sc: PackedScene = load(M + "mechcat.glb")
	if sc:
		_mech_mdl = sc.instantiate()
		ModelUtil.snap_to_ground(_mech_mdl, 6.0)
		mechcat.add_child(_mech_mdl)
		_mech_base_y = _mech_mdl.position.y
	var l := OmniLight3D.new()
	l.light_color = Color.RED
	l.light_energy = 3.0
	l.omni_range = 20
	l.position.y = 5
	mechcat.add_child(l)
	_mech_light = l
	# 枪械可命中区域（layer 2，武器射线 mask=3 可打中）
	# 实测模型视觉盒 7.5×8.2×7.5（×6），命中盒按视觉略内缩，避免隔空中弹
	var ha := Area3D.new()
	ha.name = "HitArea"
	ha.collision_layer = 2
	ha.collision_mask = 0
	mechcat.add_child(ha)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(7.0, 7.6, 7.0)
	cs.shape = sh
	cs.position = Vector3(0, 3.8, 0)
	ha.add_child(cs)

## 播放 NPC 模型的动画（KayKit 模型内置 AnimationPlayer）
func _play_npc_anim(mdl: Node, anim: String) -> void:
	var ap := mdl.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation(anim):
		ap.play(anim)

## 枪械命中机甲猫（武器系统沿父链找到本节点）：按 25 伤害=1 格折算
func bullet_hit(amount: float) -> bool:
	if stage != Stage.FIGHT:
		return false
	_mech_punch = 1.0
	mechcat_hp -= max(1, int(amount / 25.0))
	var dir := (mechcat.global_position - player.global_position)
	dir.y = 0
	mechcat.global_position += dir.normalized() * 1.5
	if mechcat_hp <= 0:
		_defeat_mechcat()
		return true
	_msg("命中！咪咪剩余 %d/5" % mechcat_hp)
	return false

func _spawn_police_station() -> void:
	var b := Node3D.new()
	b.name = "警局"
	b.position = POLICE_STATION
	add_child(b)
	var st: PackedScene = load("res://Kenney 城市套件·商业区/Models/GLB format/建筑_a.glb")
	if st:
		var mdl: Node3D = st.instantiate()
		ModelUtil.snap_to_ground(mdl, 10.0)
		b.add_child(mdl)
	var car_sc: PackedScene = load(M + "police.glb")
	if car_sc:
		var car: Node3D = car_sc.instantiate()
		car.position = Vector3(15, 0, 5)
		ModelUtil.snap_to_ground(car, 6.0)
		b.add_child(car)

# ---------- 阶段推进 ----------
func _physics_process(delta: float) -> void:
	if player == null:
		return
	# 待机/找猫阶段老奶奶缓慢面向玩家（不会背身说话）
	if stage == Stage.IDLE or stage == Stage.FIND_CAT:
		_idle_face_player(delta)
	# 机甲猫只要在场就有悬浮/灯光脉动的程序化动画
	if mechcat and mechcat.visible and is_instance_valid(mechcat):
		_animate_mechcat(delta)
	match stage:
		Stage.FIND_CAT:
			if player.global_position.distance_to(CAT_POS) < FIGHT_R:
				stage = Stage.FIGHT
				if minimap:
					minimap.remove_marker("cat")
					minimap.set_focus("mechcat")
					minimap.add_marker("mechcat", CAT_POS, Color.RED, "咪咪?", "q_cat")
				_msg("红点处蹲着的就是它……等等，那是咪咪？不对，是机甲猫！用枪打它，或靠近按跳跃键攻击！")
		Stage.FIGHT:
			_fight(delta)
		Stage.CHASE:
			_chase(delta)

func _idle_face_player(delta: float) -> void:
	if granny == null:
		return
	var d: Vector3 = player.global_position - granny.global_position
	d.y = 0
	if d.length() > 0.5:
		var want: float = atan2(d.x, d.z)
		granny.rotation.y = lerp_angle(granny.rotation.y, want, clampf(delta * 3.0, 0.0, 1.0))

## 机甲猫程序化动画：悬浮起伏 + 机身微摆 + 红眼灯脉动 + 受击缩放回弹
func _animate_mechcat(delta: float) -> void:
	_anim_t += delta
	_mech_punch = maxf(0.0, _mech_punch - delta * 4.0)
	var moving: bool = stage == Stage.FIGHT
	if _mech_mdl and is_instance_valid(_mech_mdl):
		var bob_hz: float = 3.2 if moving else 1.6
		var bob_amp: float = 0.18 if moving else 0.12
		_mech_mdl.position.y = _mech_base_y + sin(_anim_t * bob_hz) * bob_amp
		_mech_mdl.rotation.z = sin(_anim_t * 0.9) * 0.03
		var punch_s: float = 6.0 + _mech_punch * 0.9
		_mech_mdl.scale = Vector3.ONE * punch_s
	if _mech_light and is_instance_valid(_mech_light):
		_mech_light.light_energy = 2.4 + sin(_anim_t * 5.0) * 0.7 + _mech_punch * 6.0

func _input(event: InputEvent) -> void:
	if player == null:
		return
	if stage == Stage.FIGHT and event.is_action_pressed("jump"):
		if player.global_position.distance_to(CAT_POS) < FIGHT_R + 4:
			_hit_mechcat()

func _accept_quest() -> void:
	if stage != Stage.IDLE:
		return
	stage = Stage.FIND_CAT
	# 一接任务猫就在红点处现身（以前要走到 14 米内才 visible，玩家经常找不到）
	mechcat.visible = true
	if minimap:
		# 任务专注：隐藏其它所有标记，只留当前目标
		minimap.set_focus("cat")
		minimap.remove_marker("granny")
		minimap.add_marker("cat", CAT_POS, Color.RED, "找猫", "q_cat")
	_msg("老奶奶：帮我找找我的猫，它叫咪咪。就在前面不远处（红点），走几步就到！")

func _fight(delta: float) -> void:
	if not is_instance_valid(mechcat):
		return
	# 机甲猫逼近 + 车门拍打（靠近伤血）
	var dir := player.global_position - mechcat.global_position
	dir.y = 0
	if dir.length() > 3.5:
		mechcat.global_position += dir.normalized() * 3.0 * delta
	elif Engine.get_physics_frames() % 60 == 0:
		# 车门拍打：玩家掉血
		if player.has_method("take_damage"):
			player.take_damage(8.0)
			_msg("机甲猫用车门拍打你！血量-%d  剩余HP:%d" % [8, player.hp])
	# 平滑转向（避免硬切镜头跳变）
	var want_yaw: float = atan2(dir.x, dir.z)
	mechcat.rotation.y = lerp_angle(mechcat.rotation.y, want_yaw, clampf(delta * 6.0, 0.0, 1.0))

func _hit_mechcat() -> void:
	mechcat_hp -= 1
	_mech_punch = 1.0
	var dir := (mechcat.global_position - player.global_position)
	dir.y = 0
	mechcat.global_position += dir.normalized() * 3.0
	if mechcat_hp <= 0:
		_defeat_mechcat()
	else:
		_msg("命中！咪咪剩余 %d/5" % mechcat_hp)

func _defeat_mechcat() -> void:
	stage = Stage.FINE
	if minimap: minimap.remove_marker("mechcat")
	# 真猫现身
	var cat_sc: PackedScene = load(M + "cat.glb")
	if cat_sc:
		var cat: Node3D = cat_sc.instantiate()
		var ground: Vector3 = mechcat.global_position + Vector3(3, 0, 0)
		cat.position = ground
		# cat.glb 高41单位且原点居中，×0.025 ≈ 1米高真猫，并按地面高度贴地
		ModelUtil.snap_to_ground(cat, 0.025, ground.y)
		add_child(cat)
	mechcat.queue_free()
	# 报警 + 罚款 1000
	player.coins = max(0, player.coins - 1000)
	_refresh_coins()
	_msg("你因虐待动物被罚款 1000 元！")
	await get_tree().create_timer(3.0).timeout
	_start_chase()

func _start_chase() -> void:
	stage = Stage.CHASE
	chase_t = CHASE_TIME
	# 老奶奶红眼暴走 + 传送到玩家附近
	granny.global_position = player.global_position + Vector3(20, 0, 20)
	_granny_red_eyes()
	if minimap:
		minimap.set_focus("granny_chase")
		minimap.add_marker("granny_chase", granny.global_position, Color(1, 0, 0), "老奶奶!")
	_msg("老奶奶红眼暴走：我的咪咪！你赔我咪咪！快跑 %d 秒！" % int(chase_t))

func _granny_red_eyes() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color.RED
	l.light_energy = 2.0
	l.omni_range = 8
	l.position = Vector3(0, 1.5, 0)
	granny.add_child(l)
	# 追击时播跑步动画
	if granny.get_child_count() > 0:
		_play_npc_anim(granny.get_child(0), "Running_A")

func _chase(delta: float) -> void:
	chase_t -= delta
	# 老奶奶追击（移速略低于玩家奔跑，会抄近路直线追）
	var dir := player.global_position - granny.global_position
	dir.y = 0
	var dist := dir.length()
	granny.global_position += dir.normalized() * chase_speed * delta
	granny.rotation.y = atan2(dir.x, dir.z)
	if minimap and Engine.get_physics_frames() % 20 == 0:
		minimap.add_marker("granny_chase", granny.global_position, Color(1, 0, 0), "老奶奶!")
	_msg("躲避老奶奶！剩余 %d 秒" % int(ceil(chase_t)))
	# 触碰即死
	if dist < 2.0:
		_msg("被老奶奶抓住了！")
		if player.has_method("take_damage"):
			player.take_damage(999.0)  # 即死，重生
		# 重生后重新计时（player.die 会 reload，task 重来）
		return
	if chase_t <= 0.0:
		_survived()

func _survived() -> void:
	stage = Stage.DONE
	if minimap:
		minimap.remove_marker("granny_chase")
		# 任务结束：恢复所有被专注模式藏掉的标记
		minimap.clear_focus()
		minimap.add_marker("police", POLICE_STATION, Color(0.3, 0.5, 1), "警局")
	# 老奶奶停下
	_msg("你活下来了。老奶奶去报警了。（任务完成）")
