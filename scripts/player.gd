extends CharacterBody3D

signal coin_collected

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Properties")
@export var movement_speed = 250
@export var run_speed = 480          ## 奔跑速度（按住 Shift）
@export var jump_strength = 7

@export_subgroup("生存")
@export var max_hp := 100.0
@export var max_stamina := 100.0
@export var stamina_drain := 22.0    ## 奔跑每秒耗耐力
@export var stamina_regen := 16.0    ## 站立/行走每秒回耐力

signal hp_changed(hp, max_hp)
signal stamina_changed(st, max_st)

var hp := 100.0
var stamina := 100.0
var movement_velocity: Vector3
var rotation_direction: float
var gravity = 0

## 武器系统接管动画/朝向（由 WeaponSystem 每帧写入）
var anim_locked := ""
var aim_facing := false

## 商店/对话等占用输入时锁定移动与跳跃（镜头仍可看）
var input_locked := false

var previously_floored = false

var jump_single = true
var jump_double = true

var coins = 0

## 死亡/受伤减速状态
var is_dead := false              ## 死亡演出期间冻结一切输入与移动
var hurt_slow_t := 0.0            ## 受伤减速剩余秒数
const HURT_SLOW_TIME := 3.0       ## 受伤后 3 秒移速减半
const HURT_SLOW_SCALE := 0.5
const LOW_HP_RATIO := 0.3         ## 30% 以下视为低血量
const LOW_HP_SLOW_SCALE := 0.75   ## 低血量时移速再降一档

@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model = $Character
@onready var animation: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

# Functions

func _physics_process(delta):

	# 死亡演出期间：完全冻结（输入/重力/动画都停），由 DeathSystem 接管镜头 UI
	if is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Handle functions

	handle_controls(delta)
	handle_gravity(delta)

	handle_effects(delta)

	# Movement

	var applied_velocity: Vector3

	# VC 手感：起速稍猛、收油即停（加速/减速曲线分离）
	var has_move_input: bool = movement_velocity.length() > 0.001
	var lerp_rate: float = 12.0 if has_move_input else 15.0
	applied_velocity = velocity.lerp(movement_velocity, delta * lerp_rate)
	applied_velocity.y = -gravity

	velocity = applied_velocity
	move_and_slide()

	# Rotation

	var fp_face: bool = view != null and view.first_person and view.chase == null
	if (aim_facing or fp_face) and view:
		# 瞄准/开火/第一人称时面向相机正前方（镜头转向与角色精确同步）
		rotation.y = lerp_angle(rotation.y, view.rotation.y + PI, delta * 14)
	else:
		if Vector2(velocity.z, velocity.x).length() > 0:
			rotation_direction = Vector2(velocity.z, velocity.x).angle()

		rotation.y = lerp_angle(rotation.y, rotation_direction, delta * 10)

	# Falling/respawning（掉出世界走死亡演出→医院复活，不再重载场景）

	if position.y < -10:
		die()

	# Animation for scale (jumping and landing)

	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)

	# Animation when landing

	if is_on_floor() and gravity > 2 and !previously_floored:
		model.scale = Vector3(1.25, 0.75, 1.25)
		Audio.play("res://sounds/land.ogg")

	previously_floored = is_on_floor()

# Handle animation(s)

func handle_effects(delta):

	particles_trail.emitting = false
	sound_footsteps.stream_paused = true

	# 武器系统接管动画（瞄准/射击/换弹）
	if anim_locked != "":
		if animation.current_animation != anim_locked:
			animation.play(anim_locked, 0.08)
		animation.speed_scale = 1.0
		return

	if is_on_floor():
		var horizontal_velocity = Vector2(velocity.x, velocity.z)
		var speed_factor = horizontal_velocity.length() / movement_speed / delta
		if speed_factor > 0.05:
			if speed_factor > 0.6 and animation.current_animation != "Running_A":
				animation.play("Running_A", 0.1)
			elif speed_factor <= 0.6 and animation.current_animation != "Walking_A":
				animation.play("Walking_A", 0.1)

			if speed_factor > 0.3:
				sound_footsteps.stream_paused = false
				sound_footsteps.pitch_scale = speed_factor

			if speed_factor > 0.75:
				particles_trail.emitting = true

		elif animation.current_animation != "Idle":
			animation.play("Idle", 0.1)
			
		if animation.current_animation == "Walking_A" or animation.current_animation == "Running_A":
			animation.speed_scale = clamp(speed_factor, 0.3, 2.0)
		else:
			animation.speed_scale = 1.0
			
	elif animation.current_animation != "Jump_Idle":
		animation.play("Jump_Idle", 0.1)

# Handle movement input

func handle_controls(delta):

	# Movement

	var input := Vector3.ZERO

	if input_locked:
		# 商店面板打开期间：停止移动、禁止跳跃，仅恢复耐力
		movement_velocity = Vector3.ZERO
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
		stamina_changed.emit(stamina, max_stamina)
		return

	input.x = Input.get_axis("move_left", "move_right")
	input.z = Input.get_axis("move_forward", "move_back")

	input = input.rotated(Vector3.UP, view.rotation.y)

	if input.length() > 1:
		input = input.normalized()

	# 奔跑：按住 Shift 且有耐力时加速
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and stamina > 1.0 and input.length() > 0.1
	var speed: float = run_speed if running else float(movement_speed)
	# 受伤减速：刚受伤的 3 秒速度减半；血量低于 30% 时持续腿软（再降 25%）
	hurt_slow_t = maxf(0.0, hurt_slow_t - delta)
	if hurt_slow_t > 0.0:
		speed *= HURT_SLOW_SCALE
	if hp / maxf(max_hp, 1.0) < LOW_HP_RATIO:
		speed *= LOW_HP_SLOW_SCALE
	movement_velocity = input * speed * delta

	# 耐力：奔跑消耗，否则恢复
	if running:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, max_stamina)

	# Jumping

	if Input.is_action_just_pressed("jump"):

		if jump_single or jump_double:
			jump()

# Handle gravity

func handle_gravity(delta):

	gravity += 25 * delta

	if gravity > 0 and is_on_floor():

		jump_single = true
		gravity = 0

# Jumping

func jump():

	Audio.play("res://sounds/jump.ogg")

	gravity = -jump_strength

	model.scale = Vector3(0.5, 1.5, 0.5)

	if jump_single:
		jump_single = false;
		jump_double = true;
	else:
		jump_double = false;

# Collecting coins

func collect_coin():

	coins += 1

	coin_collected.emit(coins)


## 走台阶：允许踏上低台阶（楼梯/路缘），不用跳
func _ready():
	# floor_snap 更长 + 允许较小阻挡角，配合碰撞盒可走上 ~0.4m 台阶
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	# 碰撞层：玩家留在 layer 1（世界/地面都在 1，StaticBody 的 mask 默认只含 1，
	# 改层会穿地），mask 追加 layer 4（行人 NPC），NPC 之间互不碰撞由 NPC 侧配置
	collision_mask = 1 | 4
	# 挂载武器系统（主场景子节点设置阶段不能直接 add_child，延迟到设置完成后）
	call_deferred("_mount_weapon")

func _mount_weapon() -> void:
	var ws := Node3D.new()
	ws.name = "WeaponSystem"
	ws.set_script(load("res://scripts/weapon_system.gd"))
	add_child(ws)


## 受伤 / 治疗
func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(0.0, hp - amount)
	hurt_slow_t = HURT_SLOW_TIME
	hp_changed.emit(hp, max_hp)
	# 受击屏幕震动（镜头脚本提供）
	if view and view.has_method("add_shake"):
		view.add_shake(0.12 + clampf(amount / 100.0, 0.0, 1.0) * 0.12)
	if hp <= 0.0:
		die()

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

## 死亡：冻结玩家并把演出交给 DeathSystem（红屏→死亡→黑屏→医院复活）
func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	if animation and animation.has_animation("Death_A"):
		animation.play("Death_A", 0.2)
	var ds := get_tree().current_scene.get_node_or_null("DeathSystem")
	if ds and ds.has_method("play_dead"):
		ds.play_dead(self)
	else:
		# 兜底：死亡系统缺失时直接满血红场（不应发生）
		is_dead = false
		hp = max_hp
		hp_changed.emit(hp, max_hp)

## DeathSystem 在黑场中调用：医院位置复活、满血、解除一切负面状态
func revive_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	gravity = 0.0
	movement_velocity = Vector3.ZERO
	hp = max_hp
	stamina = max_stamina
	hurt_slow_t = 0.0
	is_dead = false
	model.scale = Vector3.ONE
	if animation:
		animation.play("Idle", 0.15)
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
