extends Node3D
## 下棋老头（碰瓷任务）+ 最终BOSS老奶奶 + 老头调节器
## 与 quest_system 协同：quest_system 管找猫/追杀，本脚本管下棋/BOSS/调节器

const M := "res://models/"
const CHESS_POS := Vector3(-240, 5.95, 110)   # 中央公园长椅旁（主城地面 y=5.95）

enum CStage { IDLE, PLAYING, BOSS, DOWN, FINED, DONE }
var cstage := CStage.IDLE

var player: CharacterBody3D
var minimap: CanvasLayer
var quest: Node
var oldman: Node3D
var oldman_hp := 8
var has_regulator := false

signal msg_changed(text)

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	player = get_tree().get_first_node_in_group("player")
	minimap = get_parent().get_node_or_null("Minimap")
	quest = get_parent().get_node_or_null("QuestSystem")
	_spawn_chess_oldman()
	if minimap:
		minimap.add_marker("chess", CHESS_POS, Color(0.9, 0.6, 1.0), "下棋老头")

func _msg(t: String) -> void:
	if quest and quest.has_method("_msg"):
		quest._msg(t)
	else:
		print("[老头] ", t)

func _spawn_chess_oldman() -> void:
	oldman = Node3D.new()
	oldman.name = "下棋老头"
	oldman.position = CHESS_POS
	add_child(oldman)
	# KayKit 兜帽盗贼（抽象下棋老头，贴地，坐着下棋）
	var sc: PackedScene = load(M + "kaykit/Rogue_Hooded.glb")
	if sc:
		var mdl: Node3D = sc.instantiate()
		ModelUtil.snap_to_ground(mdl, 1.0)
		oldman.add_child(mdl)
		var ap := mdl.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("Sit_Chair_Idle"):
			ap.play("Sit_Chair_Idle")
	# 枪械可命中区域（layer 2）
	var ha := Area3D.new()
	ha.name = "HitArea"
	ha.collision_layer = 2
	ha.collision_mask = 0
	oldman.add_child(ha)
	var hcs := CollisionShape3D.new()
	var hsh := CapsuleShape3D.new()
	hsh.radius = 0.6
	hsh.height = 2.0
	hcs.shape = hsh
	hcs.position = Vector3(0, 1, 0)
	ha.add_child(hcs)
	# 棋盘（小方桌）
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 0.2, 2)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.45, 0.3)
	board.material_override = mat
	board.position = Vector3(2, 1, 0)
	oldman.add_child(board)
	# GTA 式黄色任务光圈：走进圈即触发下棋
	var mk: Node = Node3D.new()
	mk.set_script(load("res://scripts/quest_marker.gd"))
	add_child(mk)
	mk.setup(CHESS_POS, Color(1.0, 0.85, 0.25), "陪老头下棋")
	mk.connect("triggered", Callable(self, "_start_chess"))

func _physics_process(delta: float) -> void:
	if player == null:
		return
	match cstage:
		CStage.PLAYING:
			_playing()
		CStage.BOSS:
			_boss_fight(delta)

func _input(event: InputEvent) -> void:
	if player == null:
		return
	if cstage == CStage.BOSS and event.is_action_pressed("jump"):
		if player.global_position.distance_to(oldman.global_position) < 16:
			_hit_oldman()

# ---------- 下棋 ----------
func _start_chess() -> void:
	if cstage != CStage.IDLE:
		return
	cstage = CStage.PLAYING
	_msg("老头：来，陪我下盘棋。（下棋中……）")

func _playing() -> void:
	# AI 极弱，2 秒后玩家必胜
	cstage = CStage.BOSS
	_win_chess()

func _win_chess() -> void:
	_msg("你赢了！老头：不可能！我下了六十年棋！（掀翻棋盘，变身BOSS）")
	oldman_hp = 8
	if minimap:
		minimap.remove_marker("chess")
		minimap.add_marker("chessboss", oldman.global_position, Color.RED, "BOSS老头")
	# 变红
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.4, 0.2)
	l.light_energy = 2.5
	l.omni_range = 5
	l.position = Vector3(0, 1.5, 0)
	oldman.add_child(l)
	# 变身 BOSS 站起来追人
	var mdl0 := oldman.get_child(0)
	var ap0 := mdl0.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap0 and ap0.has_animation("Running_A"):
		ap0.play("Running_A")

func _boss_fight(delta: float) -> void:
	if not is_instance_valid(oldman):
		return
	# 老头逼近 + 太极攻击
	var dir := player.global_position - oldman.global_position
	dir.y = 0
	if dir.length() > 3.0:
		oldman.global_position += dir.normalized() * 4.5 * delta
	elif Engine.get_physics_frames() % 50 == 0:
		if player.has_method("take_damage"):
			player.take_damage(6.0)
			_msg("老头太极拳！血量-6  剩余HP:%d" % player.hp)
	oldman.rotation.y = atan2(dir.x, dir.z)

func _hit_oldman() -> void:
	oldman_hp -= 1
	var dir := (oldman.global_position - player.global_position)
	dir.y = 0
	oldman.global_position += dir.normalized() * 2.5
	if oldman_hp <= 0:
		_oldman_down()
	else:
		_msg("命中老头！剩余 %d/8" % oldman_hp)

## 枪械命中老头 BOSS（武器系统沿父链找到本节点）：25 伤害=1 格
func bullet_hit(amount: float) -> bool:
	if cstage != CStage.BOSS:
		return false
	oldman_hp -= max(1, int(amount / 25.0))
	var dir := (oldman.global_position - player.global_position)
	dir.y = 0
	oldman.global_position += dir.normalized() * 1.2
	if oldman_hp <= 0:
		_oldman_down()
		return true
	_msg("命中老头！剩余 %d/8" % oldman_hp)
	return false

func _oldman_down() -> void:
	# 不倒下，进入碰瓷状态
	cstage = CStage.DOWN
	if minimap: minimap.remove_marker("chessboss")
	_msg("老头：哎哟！打人了！年轻人打老人了！（周围老头围拢，交通局旋转车赶到）")
	# 触发交通局通缉 + 罚款 50000
	var tp := get_parent().get_node_or_null("TrafficPolice")
	if tp and tp.has_method("set_wanted"):
		tp.set_wanted(true)
	player.coins = max(0, player.coins - 50000)
	player.coin_collected.emit(player.coins)
	cstage = CStage.FINED
	_msg("你赢了棋局，输了人生。被罚款 50000 元！")
	await get_tree().create_timer(4.0).timeout
	cstage = CStage.DONE
	# 概率掉落老头调节器碎片 → 给调节器
	_give_regulator()

# ---------- 老头调节器 ----------
func _give_regulator() -> void:
	has_regulator = true
	_msg("获得【老头调节器】！按 G 使用：全街道NPC变老头。\"你是不是很无聊？就是因为无聊。\"")

func _unhandled_input(event: InputEvent) -> void:
	if has_regulator and event.is_action_pressed("ui_text_completion_accept") == false and event is InputEventKey and event.pressed and event.keycode == KEY_G:
		_use_regulator()

func _use_regulator() -> void:
	if not has_regulator:
		return
	# 把老奶奶/机甲猫等 NPC 变老头（简化：把 quest 的老奶奶换成老头模型）
	if quest and is_instance_valid(quest.granny):
		var g: Node3D = quest.granny
		for c in g.get_children():
			if c is Node3D and c.name != "Exclaim":
				c.queue_free()
		var sc: PackedScene = load(M + "kaykit/Rogue_Hooded.glb")
		if sc:
			var mdl: Node3D = sc.instantiate()
			ModelUtil.snap_to_ground(mdl, 1.0)
			g.add_child(mdl)
	_msg("老头调节器启动：老奶奶变成了老头，忘记追击理由。（全城老头彩蛋）")
	has_regulator = false
