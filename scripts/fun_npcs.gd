extends Node3D
## 奇葩三件套：
## A 卖鱼强哥 —— 45 秒把会自爆的倒计时河豚抱送到城东收货点
## B 广场舞之王 —— 8 拍方向键斗舞 QTE，赢了得迪斯科头盔
## C 路灯外星人 —— 伪装成路灯的外星人，捡易拉罐换外星枪涂装
## 所有点位运行时射线贴地，挂在 main 根下（位置即世界坐标）

const M := "res://models/"

const FISH_XZ := Vector2(190, -15)      # 强哥鱼摊
const DELIVER_XZ := Vector2(30, 70)     # 河豚收货点
const DANCE_XZ := Vector2(85, 35)       # 广场舞场
const ALIEN_XZ := Vector2(-70, -30)     # 路灯外星人
const CAN_XZS: Array[Vector2] = [
	Vector2(140, -35), Vector2(165, 15), Vector2(120, 55), Vector2(95, -85),
	Vector2(60, 55), Vector2(25, -20), Vector2(10, 95), Vector2(-30, 30),
	Vector2(-80, -5), Vector2(200, 80),
]

enum FStage { IDLE, GOING, DONE }
enum BStage { IDLE, QTE, DONE }
enum CStage { IDLE, COLLECT, DONE }

var player: CharacterBody3D
var minimap: CanvasLayer
var quest: Node

var fstage := FStage.IDLE
var bstage := BStage.IDLE
var cstage := CStage.IDLE

# A 河豚
var fish_root: Node3D
var fish_mat: StandardMaterial3D
var fish_light: OmniLight3D
var fish_t := 0.0
const FISH_TIME := 45.0
var deliver_ring: Node
var _fish_msg_acc := 0.0

# B 斗舞
var dancer: Node3D
var dance_light: OmniLight3D
var qte_layer: CanvasLayer
var qte_panel: Control
var qte_round := 0
var qte_ok := 0
var qte_bad := 0
var qte_dir := 0
var qte_t := 0.0
var qte_flash := 0.0
const QTE_BEATS := 8
const QTE_WIN := 6
const QTE_WINDOW := 1.35
const DIRS_KEY: Array[int] = [KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_LEFT]

# C 易拉罐
var alien_root: Node3D
var alien_head: Node3D
var alien_lamp: MeshInstance3D
var alien_lamp_mat: StandardMaterial3D
var cans_root: Node3D
var cans: Array[Node3D] = []
var can_beams: Array[StandardMaterial3D] = []
var cans_got := 0
var cans_total := 0

# 迪斯科头盔
var helmet_pivot: Node3D
var helmet_lights: Array[OmniLight3D] = []

var _t := 0.0
var _dance_y := 5.95

func _ready() -> void:
	_setup()

func _setup() -> void:
	# 等世界/玩家就绪再射线贴地
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		# 再等等
		for i in 60:
			await get_tree().process_frame
			player = get_tree().get_first_node_in_group("player")
			if player:
				break
	minimap = get_parent().get_node_or_null("Minimap")
	quest = get_parent().get_node_or_null("QuestSystem")
	_spawn_fishguy()
	_spawn_dancer()
	_spawn_alien()
	cans_root = Node3D.new()
	cans_root.name = "易拉罐们"
	add_child(cans_root)
	_build_qte_ui()
	if minimap:
		minimap.add_marker("fishn", Vector3(FISH_XZ.x, _gy(FISH_XZ), FISH_XZ.y), Color(1, 0.85, 0.25), "卖鱼强哥", "q_fish")
		minimap.add_marker("dancen", Vector3(DANCE_XZ.x, _gy(DANCE_XZ), DANCE_XZ.y), Color(1, 0.35, 0.8), "广场舞之王", "q_dance")
		minimap.add_marker("alienen", Vector3(ALIEN_XZ.x, _gy(ALIEN_XZ), ALIEN_XZ.y), Color(0.5, 1, 0.4), "神秘路灯", "q_alien")
	_msg("城里来了三个怪人：卖鱼强哥（黄点）、广场舞大妈（粉点）、还有个成精的路灯（绿点）")

func _msg(t: String) -> void:
	if quest and quest.has_method("_msg"):
		quest._msg(t)
	else:
		print("[怪人] ", t)

func _coins(n: int) -> void:
	player.coins += n
	player.coin_collected.emit(player.coins)

## 射线贴地
func _gy(xz: Vector2) -> float:
	if player == null:
		return 5.95
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 14.0, xz.y), Vector3(xz.x, -8.0, xz.y), 1, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		var p: Vector3 = hit["position"]
		return p.y
	return 5.95

func _ring(pos: Vector3, col: Color, title: String, cb: Callable) -> Node:
	var mk := Node3D.new()
	mk.set_script(load("res://scripts/quest_marker.gd"))
	add_child(mk)
	mk.setup(pos, col, title)
	mk.connect("triggered", cb)
	return mk

func _billboard(text: String, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.03, 0.08)
	l.position.y = y
	return l

# ======================================================================
# A 卖鱼强哥
# ======================================================================
func _spawn_fishguy() -> void:
	var pos := Vector3(FISH_XZ.x, _gy(FISH_XZ), FISH_XZ.y)
	var n := Node3D.new()
	n.name = "卖鱼强哥"
	n.position = pos
	add_child(n)
	var sc: PackedScene = load(M + "kaykit/Barbarian.glb")
	if sc:
		var mdl: Node3D = sc.instantiate()
		ModelUtil.snap_to_ground(mdl, 1.0)
		n.add_child(mdl)
		var ap := mdl.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("Idle"):
			ap.play("Idle")
	n.add_child(_billboard("卖鱼强哥", Color(1, 0.85, 0.25), 3.4))
	# 鱼摊：木箱 + 上面摆一条样品河豚
	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.45, 0.3, 0.15)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 1.0, 1.0)
	box.mesh = bm
	box.material_override = table_mat
	box.position = Vector3(2.0, 0.5, 0)
	n.add_child(box)
	var sample := _make_puffer(0.7)
	sample.position = Vector3(2.0, 1.25, 0)
	n.add_child(sample)
	# 橡胶鸡（抽象：黄棒鸡，插在摊上）
	var chk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.12
	cm.height = 1.1
	chk.mesh = cm
	var chkm := StandardMaterial3D.new()
	chkm.albedo_color = Color(1, 0.85, 0.2)
	chk.material_override = chkm
	chk.position = Vector3(2.6, 1.7, 0.4)
	chk.rotation_degrees.z = -18
	n.add_child(chk)
	_ring(pos, Color(1, 0.85, 0.25), "强哥的急件", Callable(self, "_start_fish"))

func _start_fish() -> void:
	if fstage != FStage.IDLE:
		return
	fstage = FStage.GOING
	fish_t = FISH_TIME
	if minimap:
		minimap.remove_marker("fishn")
	# 收货点光圈（只建一次，失败重试时复用）
	if deliver_ring == null or not is_instance_valid(deliver_ring):
		var dpos := Vector3(DELIVER_XZ.x, _gy(DELIVER_XZ), DELIVER_XZ.y)
		deliver_ring = _ring(dpos, Color(0.4, 1, 0.5), "河豚收货点", Callable(self, "_fish_deliver"))
	# 抱着的河豚挂玩家身上
	fish_root = Node3D.new()
	fish_root.name = "倒计时河豚"
	player.add_child(fish_root)
	_build_fish_visual(fish_root)
	fish_root.position = Vector3(0.75, 1.75, 0.7)
	if minimap:
		minimap.add_marker("fdeliv", deliver_ring.global_position, Color(0.4, 1, 0.5), "快送河豚!")
	_msg("强哥：这条河豚还有 45 秒就炸！抱去城东绿圈收货点，到了给你 300 块！别跑太颠——！")

func _build_fish_visual(root: Node3D) -> void:
	fish_mat = StandardMaterial3D.new()
	fish_mat.albedo_color = Color(1, 0.8, 0.2)
	fish_mat.emission_enabled = true
	fish_mat.emission = Color(0.5, 0.15, 0.0)
	fish_mat.emission_energy_multiplier = 0.4
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	body.mesh = sm
	body.material_override = fish_mat
	root.add_child(body)
	# 刺（用小球做鼓包，省朝向计算）
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.9, 0.7, 0.15)
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		var elev: float = -0.5 + float(i % 3) * 0.5
		var dir := Vector3(cos(a) * cos(elev), sin(elev), sin(a) * cos(elev))
		var sp := MeshInstance3D.new()
		var ssp := SphereMesh.new()
		ssp.radius = 0.09
		ssp.height = 0.18
		sp.mesh = ssp
		sp.material_override = spike_mat
		sp.position = dir * 0.42
		root.add_child(sp)
	# 眼睛
	for sx in [-0.16, 0.16]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.1
		em.height = 0.2
		eye.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color.BLACK
		eye.material_override = emat
		eye.position = Vector3(sx, 0.08, 0.36)
		root.add_child(eye)
	fish_light = OmniLight3D.new()
	fish_light.light_color = Color(1, 0.3, 0.1)
	fish_light.light_energy = 0.0
	fish_light.omni_range = 6.0
	fish_light.position = Vector3(0, 0.2, 0)
	root.add_child(fish_light)

func _tick_fish(delta: float) -> void:
	fish_t -= delta
	var urg: float = 1.0 - clampf(fish_t / FISH_TIME, 0.0, 1.0)
	if fish_mat:
		fish_mat.albedo_color = Color(1.0, lerp(0.8, 0.15, urg), lerp(0.2, 0.05, urg))
		fish_mat.emission_energy_multiplier = 0.4 + urg * 1.2
	# 越急鼓得越大、抖得越凶
	if fish_root:
		var s: float = 1.0 + sin(_t * (4.0 + urg * 10.0)) * 0.05 + urg * 0.25
		fish_root.scale = Vector3.ONE * s
		fish_root.rotation.z = sin(_t * (6.0 + urg * 14.0)) * 0.12
	if fish_light:
		fish_light.light_energy = 3.0 + sin(_t * (6.0 + urg * 14.0)) * 2.5
	_fish_msg_acc -= delta
	if _fish_msg_acc <= 0.0:
		_fish_msg_acc = 0.4
		if int(fish_t) <= 10:
			_msg("嘀嘀嘀——！%d 秒！要炸了！！" % int(max(0, fish_t)))
		else:
			_msg("抱稳河豚！剩余 %d 秒（绿点是收货点）" % int(fish_t))
	if fish_t <= 0.0:
		_fish_explode()

func _fish_explode() -> void:
	fstage = FStage.IDLE
	if is_instance_valid(fish_root):
		fish_root.queue_free()
	if minimap:
		minimap.remove_marker("fdeliv")
	if player.has_method("take_damage"):
		player.take_damage(20.0)
	_msg("砰！！！河豚炸了，你被崩成了墨鱼卷。回去找强哥，他说免费给你续一条……")
	# 强哥的黄圈重新摆上
	var pos := Vector3(FISH_XZ.x, _gy(FISH_XZ), FISH_XZ.y)
	_ring(pos, Color(1, 0.85, 0.25), "强哥的急件（重试）", Callable(self, "_start_fish"))

func _fish_deliver() -> void:
	if fstage != FStage.GOING:
		return
	fstage = FStage.DONE
	if is_instance_valid(fish_root):
		fish_root.queue_free()
	if minimap:
		minimap.remove_marker("fdeliv")
	_coins(300)
	_msg("强哥：行啊兄弟！300 块拿好！这鱼我亲手做，吃了能看见我太奶。")

## 鱼摊上的样品小河豚（圆身+鼓包刺）
func _make_puffer(sc: float) -> Node3D:
	var p := Node3D.new()
	p.scale = Vector3.ONE * sc
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 0.75, 0.25)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	body.mesh = sm
	body.material_override = bmat
	p.add_child(body)
	var sp_mat := StandardMaterial3D.new()
	sp_mat.albedo_color = Color(0.9, 0.7, 0.15)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		var sp := MeshInstance3D.new()
		var ssp := SphereMesh.new()
		ssp.radius = 0.08
		ssp.height = 0.16
		sp.mesh = ssp
		sp.material_override = sp_mat
		sp.position = Vector3(cos(a) * 0.42, 0.1 * sin(float(i * 2.0)), sin(a) * 0.42)
		p.add_child(sp)
	return p

# ======================================================================
# B 广场舞之王
# ======================================================================
func _spawn_dancer() -> void:
	_dance_y = _gy(DANCE_XZ)
	var pos := Vector3(DANCE_XZ.x, _dance_y, DANCE_XZ.y)
	dancer = Node3D.new()
	dancer.name = "广场舞之王"
	dancer.position = pos
	add_child(dancer)
	var sc: PackedScene = load(M + "kaykit/Rogue.glb")
	if sc:
		var mdl: Node3D = sc.instantiate()
		ModelUtil.snap_to_ground(mdl, 0.95)
		dancer.add_child(mdl)
		var ap := mdl.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("Idle"):
			ap.play("Idle")
	dancer.add_child(_billboard("广场舞之王", Color(1, 0.35, 0.8), 3.4))
	# 霓虹舞池圈
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.7
	tm.outer_radius = 2.2
	ring.mesh = tm
	ring.rotation_degrees.x = 90
	ring.position.y = 0.07
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.emission_enabled = true
	rm.emission = Color(1, 0.2, 0.75)
	rm.emission_energy_multiplier = 2.6
	ring.material_override = rm
	dancer.add_child(ring)
	# 发光喇叭裤（腿上俩霓虹圈）
	for yy in [0.35, 0.9]:
		var band := MeshInstance3D.new()
		var btm := TorusMesh.new()
		btm.inner_radius = 0.22
		btm.outer_radius = 0.3
		band.mesh = btm
		band.rotation_degrees.x = 90
		band.position.y = yy
		band.material_override = rm
		dancer.add_child(band)
	# 录音机
	var boom := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(0.9, 0.5, 0.3)
	boom.mesh = bm2
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.05, 0.15)
	bmat.metallic = 0.6
	boom.material_override = bmat
	boom.position = Vector3(1.6, 0.55, 0)
	dancer.add_child(boom)
	# 舞台彩灯
	dance_light = OmniLight3D.new()
	dance_light.light_color = Color(1, 0.3, 0.8)
	dance_light.light_energy = 1.6
	dance_light.omni_range = 9
	dance_light.position = Vector3(0, 2.6, 0)
	dancer.add_child(dance_light)
	_ring(pos, Color(1, 0.35, 0.8), "挑战舞王", Callable(self, "_start_dance"))

func _start_dance() -> void:
	if bstage != BStage.IDLE:
		return
	bstage = BStage.QTE
	qte_round = 0
	qte_ok = 0
	qte_bad = 0
	if minimap:
		minimap.remove_marker("dancen")
	# 定身专心斗舞
	player.set_physics_process(false)
	qte_panel.visible = true
	_msg("舞王：小伙子，能跟上我的节拍吗？方向键踩点，8 拍中 6 拍就算你赢！")
	_next_beat()

func _next_beat() -> void:
	qte_dir = (qte_dir + 1 + randi() % 3) % 4
	qte_t = QTE_WINDOW
	qte_flash = 0.0

func _end_dance(win: bool) -> void:
	bstage = BStage.IDLE if not win else BStage.DONE
	qte_panel.visible = false
	player.set_physics_process(true)
	if win:
		_coins(250)
		_give_helmet()
		_msg("舞王：行！广场以后你罩了！这顶迪斯科头盔送你，250 块出场费拿好！")
	else:
		_msg("舞王：就这？踩了 %d 拍，错 %d 拍，回家看两集广场舞教学再来！" % [qte_ok, qte_bad])
		# 重新摆圈
		await get_tree().create_timer(1.5).timeout
		var pos := Vector3(DANCE_XZ.x, _gy(DANCE_XZ), DANCE_XZ.y)
		_ring(pos, Color(1, 0.35, 0.8), "再战舞王", Callable(self, "_start_dance"))
		if minimap:
			minimap.add_marker("dancen", pos, Color(1, 0.35, 0.8), "广场舞之王", "q_dance")

func _tick_dance(delta: float) -> void:
	qte_t -= delta
	qte_flash = move_toward(qte_flash, 0.0, delta * 3.0)
	qte_panel.queue_redraw()
	if qte_t <= 0.0 and qte_t > -10.0:
		# 没踩上（哨兵 999 的间隔帧不算）
		qte_bad += 1
		qte_flash = -1.0
		qte_t = -99.0
		_advance_beat()

func _advance_beat() -> void:
	qte_round += 1
	if qte_round >= QTE_BEATS:
		_end_dance(qte_ok >= QTE_WIN)
	else:
		_next_beat_soon()

func _next_beat_soon() -> void:
	# 短暂停顿后给下一拍
	qte_t = 999.0
	await get_tree().process_frame
	await get_tree().process_frame
	if bstage == BStage.QTE:
		_next_beat()

func _unhandled_input(event: InputEvent) -> void:
	if bstage == BStage.QTE and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		for d in 4:
			if k == DIRS_KEY[d] and qte_t < 100.0:
				_judge_beat(d)
				get_viewport().set_input_as_handled()
				return

func _judge_beat(d: int) -> void:
	if d == qte_dir:
		qte_ok += 1
		qte_flash = 1.0
	else:
		qte_bad += 1
		qte_flash = -1.0
	_advance_beat()

func _build_qte_ui() -> void:
	qte_layer = CanvasLayer.new()
	qte_layer.layer = 12
	add_child(qte_layer)
	qte_panel = Control.new()
	qte_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	qte_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qte_panel.visible = false
	qte_panel.draw.connect(_draw_qte)
	qte_layer.add_child(qte_panel)

func _draw_qte() -> void:
	if bstage != BStage.QTE:
		return
	var c: Vector2 = qte_panel.size * 0.5
	var font: Font = ThemeDB.fallback_font
	# 半透明压暗
	qte_panel.draw_rect(Rect2(Vector2.ZERO, qte_panel.size), Color(0.02, 0.02, 0.05, 0.45), true)
	var good: bool = qte_flash > 0.0
	var bad: bool = qte_flash < 0.0
	var ring_col: Color = Color(0.35, 0.95, 1.0) if not bad else Color(1, 0.3, 0.4)
	# 节拍倒计时收缩环
	var frac: float = clampf(qte_t / QTE_WINDOW, 0.0, 1.0) if qte_t < 100.0 else 0.0
	var rad: float = lerpf(150.0, 70.0, 1.0 - frac)
	qte_panel.draw_arc(c, 160.0, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 6.0, true)
	qte_panel.draw_arc(c, rad, 0.0, TAU, 48, ring_col, 8.0, true)
	# 大箭头
	var col: Color = Color.WHITE
	if good:
		col = Color(0.4, 1, 0.5)
	elif bad:
		col = Color(1, 0.35, 0.4)
	if qte_t < 100.0:
		_draw_big_arrow(c, qte_dir, col)
	# 计分
	var info: String = "斗舞  %d/%d    对 %d    错 %d" % [qte_round + 1, QTE_BEATS, qte_ok, qte_bad]
	qte_panel.draw_string(font, c + Vector2(-260, 150), info, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 34, Color(1, 0.6, 0.9))
	qte_panel.draw_string(font, c + Vector2(-260, 195), "方向键 ↑ → ↓ ← 踩点", HORIZONTAL_ALIGNMENT_CENTER, 520.0, 24, Color(0.7, 0.8, 0.9))

## 自绘大箭头（朝上的多边形按方向旋转），不依赖字体里有没有箭头字形
func _draw_big_arrow(c: Vector2, dir: int, col: Color) -> void:
	var raw := PackedVector2Array([
		Vector2(0, -110), Vector2(48, -40), Vector2(20, -40), Vector2(20, 80),
		Vector2(-20, 80), Vector2(-20, -40), Vector2(-48, -40)])
	var a: float = deg_to_rad(90.0 * dir)
	var ca: float = cos(a)
	var sa: float = sin(a)
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(c + Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca))
	qte_panel.draw_colored_polygon(pts, col)
	# 深色描边
	for i in pts.size():
		qte_panel.draw_line(pts[i], pts[(i + 1) % pts.size()], Color(0.08, 0.05, 0.12), 6.0)

## 迪斯科头盔：镜面球 + 四色旋转彩灯，戴玩家头上
func _give_helmet() -> void:
	var old := player.get_node_or_null("DiscoHelmet")
	if old:
		old.queue_free()
	var h := Node3D.new()
	h.name = "DiscoHelmet"
	h.position = Vector3(0, 2.08, 0)
	player.add_child(h)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	ball.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.9, 1.0)
	bmat.metallic = 1.0
	bmat.roughness = 0.05
	ball.material_override = bmat
	h.add_child(ball)
	# 帽檐
	var brim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.42
	brim.mesh = tm
	brim.rotation_degrees.x = 90
	brim.position.y = -0.12
	var brm := StandardMaterial3D.new()
	brm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brm.emission_enabled = true
	brm.emission = Color(0.4, 1, 0.9)
	brm.emission_energy_multiplier = 2.0
	brim.material_override = brm
	h.add_child(brim)
	helmet_pivot = Node3D.new()
	helmet_pivot.position.y = 0.05
	h.add_child(helmet_pivot)
	var cols: Array[Color] = [Color(1, 0.2, 0.8), Color(0.3, 0.9, 1), Color(1, 0.9, 0.2), Color(0.4, 1, 0.3)]
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = cols[i]
		l.light_energy = 1.4
		l.omni_range = 5.0
		var a: float = TAU * float(i) / 4.0
		l.position = Vector3(cos(a) * 0.55, 0, sin(a) * 0.55)
		helmet_pivot.add_child(l)
		helmet_lights.append(l)

# ======================================================================
# C 路灯外星人
# ======================================================================
func _spawn_alien() -> void:
	var pos := Vector3(ALIEN_XZ.x, _gy(ALIEN_XZ), ALIEN_XZ.y)
	alien_root = Node3D.new()
	alien_root.name = "路灯外星人"
	alien_root.position = pos
	add_child(alien_root)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.13, 0.16)
	metal.metallic = 0.8
	metal.roughness = 0.4
	# 灯杆
	var pole := MeshInstance3D.new()
	var pm2 := CylinderMesh.new()
	pm2.top_radius = 0.1
	pm2.bottom_radius = 0.14
	pm2.height = 5.2
	pole.mesh = pm2
	pole.material_override = metal
	pole.position.y = 2.6
	alien_root.add_child(pole)
	# 横臂
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.3, 0.14, 0.14)
	arm.mesh = am
	arm.material_override = metal
	arm.position = Vector3(0.55, 5.1, 0)
	alien_root.add_child(arm)
	# 灯罩（普通路灯样）
	alien_lamp = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.18
	lm.bottom_radius = 0.38
	lm.height = 0.4
	alien_lamp.mesh = lm
	alien_lamp.position = Vector3(1.15, 4.85, 0)
	alien_lamp_mat = StandardMaterial3D.new()
	alien_lamp_mat.albedo_color = Color(1, 0.9, 0.5)
	alien_lamp_mat.emission_enabled = true
	alien_lamp_mat.emission = Color(1, 0.85, 0.45)
	alien_lamp_mat.emission_energy_multiplier = 1.6
	alien_lamp.material_override = alien_lamp_mat
	alien_root.add_child(alien_lamp)
	# 藏在灯罩里的外星大头（接任务后才露）
	alien_head = Node3D.new()
	alien_head.position = Vector3(1.15, 4.85, 0)
	alien_head.visible = false
	alien_root.add_child(alien_head)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(0.4, 1, 0.45)
	hm.emission_enabled = true
	hm.emission = Color(0.3, 1, 0.4)
	hm.emission_energy_multiplier = 1.4
	var head := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 0.55
	hsm.height = 1.1
	head.mesh = hsm
	head.material_override = hm
	alien_head.add_child(head)
	# 两只巨大的黑眼睛
	for sx in [-0.22, 0.22]:
		var eye := MeshInstance3D.new()
		var esm := SphereMesh.new()
		esm.radius = 0.17
		esm.height = 0.34
		eye.mesh = esm
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color.BLACK
		emat.roughness = 0.1
		emat.metallic = 0.3
		eye.material_override = emat
		eye.position = Vector3(sx, 0.05, 0.42)
		alien_head.add_child(eye)
	# 小天线
	var ant := MeshInstance3D.new()
	var anm := CylinderMesh.new()
	anm.top_radius = 0.02
	anm.bottom_radius = 0.03
	anm.height = 0.5
	ant.mesh = anm
	ant.material_override = hm
	ant.position = Vector3(0, 0.72, 0)
	alien_head.add_child(ant)
	alien_root.add_child(_billboard("???  路  灯  ???", Color(0.6, 1, 0.5), 6.4))
	_ring(pos, Color(0.5, 1, 0.4), "路灯找你有事", Callable(self, "_start_cans"))

func _start_cans() -> void:
	if cstage != CStage.IDLE:
		return
	cstage = CStage.COLLECT
	if minimap:
		minimap.remove_marker("alienen")
	# 露馅：路灯罩熄灭，外星大头弹出
	alien_lamp_mat.emission_energy_multiplier = 0.0
	alien_lamp_mat.albedo_color = Color(0.25, 0.25, 0.2)
	alien_head.visible = true
	if cans.is_empty():
		_spawn_cans()
	cans_total = cans.size()
	_msg("（电子杂音）路……路灯成精了：我是外星调研员。捡 %d 个你们文明的易拉罐给我，换外星武器涂装！" % cans_total)

func _spawn_cans() -> void:
	for i in CAN_XZS.size():
		var xz: Vector2 = CAN_XZS[i]
		var y: float = _gy(xz)
		var can := Node3D.new()
		can.name = "易拉罐"
		can.position = Vector3(xz.x, y, xz.y)
		cans_root.add_child(can)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.78, 0.82)
		mat.metallic = 0.9
		mat.roughness = 0.25
		var cyl := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.13
		cm2.bottom_radius = 0.13
		cm2.height = 0.34
		cyl.mesh = cm2
		cyl.material_override = mat
		cyl.rotation_degrees.z = 72
		cyl.position.y = 0.2
		can.add_child(cyl)
		# 绿色光柱，远处可见
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_mat.albedo_color = Color(0.4, 1, 0.4, 0.14)
		beam_mat.emission_enabled = true
		beam_mat.emission = Color(0.4, 1, 0.4)
		var beam := MeshInstance3D.new()
		var bm3 := CylinderMesh.new()
		bm3.top_radius = 0.22
		bm3.bottom_radius = 0.22
		bm3.height = 3.2
		beam.mesh = bm3
		beam.material_override = beam_mat
		beam.position.y = 1.7
		can.add_child(beam)
		can_beams.append(beam_mat)
		cans.append(can)
		if minimap:
			minimap.add_marker("can%d" % i, can.global_position, Color(0.5, 1, 0.4), "罐")

func _tick_cans(delta: float) -> void:
	# 光柱呼吸
	for i in can_beams.size():
		var m: StandardMaterial3D = can_beams[i]
		m.albedo_color.a = 0.08 + (sin(_t * 3.0 + float(i)) * 0.5 + 0.5) * 0.12
	# 吸取检测
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var i := cans.size() - 1
	while i >= 0:
		var can: Node3D = cans[i]
		if not is_instance_valid(can):
			cans.remove_at(i)
			i -= 1
			continue
		can.rotation.y += delta * 2.2
		var cp := Vector2(can.global_position.x, can.global_position.z)
		if pp.distance_to(cp) < 2.4:
			if minimap:
				minimap.remove_marker("can%d" % _can_marker_index(can))
			can.queue_free()
			cans.remove_at(i)
			cans_got += 1
			if cans_got < cans_total:
				_msg("易拉罐 %d/%d，塞进口袋（咣当）" % [cans_got, cans_total])
			else:
				_cans_done()
		i -= 1

## marker id 与生成序号对应
func _can_marker_index(can: Node3D) -> int:
	for i in CAN_XZS.size():
		if absf(can.global_position.x - CAN_XZS[i].x) < 0.5 \
				and absf(can.global_position.z - CAN_XZS[i].y) < 0.5:
			return i
	return 0

func _cans_done() -> void:
	cstage = CStage.DONE
	_coins(200)
	# 外星枪涂装
	var ws: Node = player.get_node_or_null("WeaponSystem")
	if ws:
		ws.set("alien_skin", true)
		ws.call("_switch", int(ws.get("current")), true)
	_msg("外星人：交易愉快。你们的武器现在有了银河系最潮的荧光绿。这 200 块是回收价。")

# ======================================================================
# 每帧：河豚倒计时 / 斗舞 / 易拉罐 / 装饰动画
# ======================================================================
func _physics_process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	if fstage == FStage.GOING:
		_tick_fish(delta)
	if bstage == BStage.QTE:
		_tick_dance(delta)
	if cstage == CStage.COLLECT:
		_tick_cans(delta)
	# 舞王摇摆
	if is_instance_valid(dancer):
		dancer.rotation.z = sin(_t * 4.0) * 0.08
		dancer.position.y = _dance_y + abs(sin(_t * 4.0)) * 0.12
		if dance_light:
			var cols2: Array[Color] = [Color(1, 0.2, 0.8), Color(0.2, 0.8, 1), Color(1, 0.9, 0.2), Color(0.4, 1, 0.4)]
			dance_light.light_color = cols2[int(_t * 3.0) % 4]
	# 头盔彩灯旋转
	if helmet_pivot and is_instance_valid(helmet_pivot):
		helmet_pivot.rotation.y += delta * 5.0
	# 外星人露馅后脑袋左右打量
	if is_instance_valid(alien_head) and alien_head.visible:
		alien_head.rotation.y = sin(_t * 1.3) * 0.5
