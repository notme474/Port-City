extends Node3D

## 昼夜循环 + 霓虹夜景：太阳旋转/昼夜色温/路灯与车灯自动点亮/月亮
## day_phase 0~1（0=正午, 0.5=午夜），可通过 _set_time_scale 加速调试

signal day_changed(day_idx: int)

const DAY_LEN := 480.0          # 现实 8 分钟 = 游戏一昼夜（8h*60s/480s=0.5, 方便调）
const NIGHT_LIGHT_ON := 0.28    # 日落到凌晨开灯
const NIGHT_LIGHT_OFF := 0.78   # 清晨关灯
# Vice City 调色板：迈阿密青蓝白天 / 品红橙黄昏 / 紫蓝深夜
const SKY_DAY := Color(0.38, 0.68, 0.96)
const SKY_DAWN := Color(1.0, 0.38, 0.5)
const SKY_NIGHT := Color(0.05, 0.07, 0.18)
const AMBIENT_DAY := Color(0.92, 0.9, 0.96)
const AMBIENT_NIGHT := Color(0.2, 0.22, 0.45)

var sun: DirectionalLight3D
var env: Environment
var moon: DirectionalLight3D
var day_phase := 0.15            # 0=正午 0.5=午夜 0.75=黎明
var day_idx := 1
var _lights: Array[Dictionary] = []  # {light, base_energy, is_car}
var _city_built := false

func _ready() -> void:
	sun = get_parent().get_node_or_null("Sun")
	env = get_parent().get_node("Environment").environment if get_parent().has_node("Environment") else null
	# 备份天空原始贴图引用（PanoramaSkyMaterial.panorama 的替代方案见 _build_sky）
	_build_sky()
	_build_moon()
	_collect_lights()
	# 初始不打断 main.gd 的 gl_compatibility 补偿，等它先跑完
	await get_tree().process_frame
	_city_built = true
	_apply(true)                  # 立即应用一次，防首帧闪白
	# 补收延迟建好的灯：Store 在 DayNight 之后才挂、city_cars 车辆是 deferred 构建，
	# 首扫会漏掉店铺灯和车大灯；2 秒后增量补扫（只加新灯，已记录的保持原基准亮度）
	await get_tree().create_timer(2.0).timeout
	_collect_lights(true)
	_apply(true)

func _build_sky() -> void:
	if env == null or env.sky == null:
		return
	# 保留原 sky_material（天空贴图），用 energy_multiplier 控制昼夜压暗
	if env.sky.sky_material is PanoramaSkyMaterial:
		var mat := env.sky.sky_material as PanoramaSkyMaterial
		mat.energy_multiplier = 1.0

func _build_moon() -> void:
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, 180, 0)
	moon.light_color = Color(0.75, 0.85, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 1200.0
	add_child(moon)

func _collect_lights(only_new := false) -> void:
	if not only_new:
		_lights.clear()
	# 找场景里所有 OmniLight/SpotLight（fun_npcs 鱼灯/舞灯/头盔、quest 猫灯、world 码头灯、车大灯）
	_scan(get_tree().root, 0)

func _scan(n: Node, depth: int) -> void:
	if depth > 12:
		return
	if n is OmniLight3D or n is SpotLight3D:
		if n == moon or n == sun:
			return
		# 排除调试灯/贴图生成器灯（uap_thumb_gen 只在导入时跑）
		if n.owner and str(n.owner.name).begins_with("UAP"):
			return
		# 增量补扫时跳过已记录的灯（避免把已被昼夜调暗的当前值误当基准亮度）
		for d in _lights:
			if d.light == n:
				return
		# 灯可用 night_energy 元数据显式声明夜间基准亮度（如 store_lamp 初始为 0）
		var be: float = n.get_meta("night_energy",
			(n as OmniLight3D).light_energy if n is OmniLight3D else (n as SpotLight3D).light_energy)
		_lights.append({
			"light": n,
			"base_energy": be,
			"is_car": str(n.name).contains("Head") or str(n.name).contains("headlight"),
		})
		return
	for c in n.get_children():
		_scan(c, depth + 1)

## 外部接口：调整游戏时间流速（调试/任务用）
func _set_time_scale(s: float) -> void:
	DAY_LEN_SCALE = s

var DAY_LEN_SCALE := 1.0

func _process(delta: float) -> void:
	day_phase = fmod(day_phase + delta / (DAY_LEN * DAY_LEN_SCALE), 1.0)
	_apply(false)

func _apply(immediate: bool) -> void:
	var night := _is_night()
	# 太阳角度：0=正午(头顶) → 0.25=日落 → 0.5=午夜(背对) → 0.75=日出
	var sun_ang := -180.0 * (day_phase * 2.0 - 1.0)  # -180~180，0.25→-90 平线
	sun.rotation_degrees.x = sun_ang
	moon.rotation_degrees.x = -sun_ang + 180.0        # 月亮永远跟太阳对顶

	# 色温：白天→黄昏→深夜
	var sky_col: Color
	var amb_col: Color
	var sun_energy: float
	var moon_energy: float
	var bg_mult: float
	var tone_exp: float
	if day_phase < 0.25:          # 上午→下午
		var f := day_phase / 0.25
		sky_col = SKY_DAY.lerp(SKY_DAWN, f * f)
		amb_col = AMBIENT_DAY
		sun_energy = lerpf(1.0, 0.55, f)
		moon_energy = 0.0
		bg_mult = lerpf(1.0, 0.6, f)
		tone_exp = lerpf(1.0, 0.8, f)
	elif day_phase < 0.35:        # 黄昏
		var f := (day_phase - 0.25) / 0.1
		sky_col = SKY_DAWN.lerp(SKY_NIGHT, f)
		amb_col = AMBIENT_DAY.lerp(Color(0.4, 0.3, 0.52), f)
		sun_energy = lerpf(0.55, 0.0, f)
		moon_energy = lerpf(0.0, 0.28, f)
		bg_mult = lerpf(0.6, 0.25, f)
		tone_exp = lerpf(0.8, 0.6, f)
	elif day_phase < 0.75:        # 深夜
		var f := (day_phase - 0.35) / 0.4
		sky_col = SKY_NIGHT
		amb_col = AMBIENT_NIGHT
		sun_energy = 0.0
		moon_energy = 0.28 * (0.7 + 0.3 * sin(f * TAU))
		bg_mult = 0.18
		tone_exp = 0.45
	else:                         # 黎明→上午
		var f := (day_phase - 0.75) / 0.25
		sky_col = SKY_NIGHT.lerp(SKY_DAY, f * f)
		amb_col = AMBIENT_NIGHT.lerp(AMBIENT_DAY, f)
		sun_energy = lerpf(0.0, 1.0, f)
		moon_energy = lerpf(0.28, 0.0, f)
		bg_mult = lerpf(0.18, 1.0, f)
		tone_exp = lerpf(0.45, 1.0, f)

	# 太阳颜色随高度变暖（VC 金橙色阳光，日出日落偏品红橙）
	if sun_energy > 0.01:
		var h := clampf(abs(sun_ang) / 90.0, 0.0, 1.0)  # 0=平线 1=头顶
		sun.light_color = Color(1.0, 0.72 + 0.2 * h, 0.5 + 0.3 * h)
		sun.light_energy = sun_energy
	else:
		sun.light_energy = 0.0

	moon.light_energy = moon_energy

	if env:
		env.background_color = sky_col
		env.ambient_light_color = amb_col
		env.background_energy_multiplier = bg_mult
		env.tonemap_exposure = tone_exp
		# 天空贴图昼夜压暗（不改贴图，只调 sky_material 的能量）
		if env.sky and env.sky.sky_material is PanoramaSkyMaterial:
			(env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = bg_mult

	# 灯光：白天关、晚上开（渐变，非瞬间）
	_update_lights(night, immediate)

func _is_night() -> bool:
	return day_phase >= NIGHT_LIGHT_ON and day_phase < NIGHT_LIGHT_OFF

func _update_lights(night: bool, _imm: bool) -> void:
	var target := 1.0 if night else 0.0
	for d in _lights:
		var l = d.light
		if not is_instance_valid(l):
			continue
		var base: float = d.base_energy
		# 车大灯特殊：白天也留一点示宽（0.15），晚上满功率
		if d.is_car:
			l.light_energy = base * (0.15 + 0.85 * target)
		else:
			# 任务灯（鱼灯/舞灯/头盔）本身就是功能灯，白天也保持功能亮度，夜景只是强化
			var nm := str(l.name)
			if nm.contains("fish") or nm.contains("dance") or nm.contains("helmet") or nm.contains("boss"):
				l.light_energy = base * (0.5 + 0.5 * target)   # 夜景强化但不灭
			else:
				l.light_energy = base * target

## 外部查询：给 HUD/任务用
func get_time_str() -> String:
	var total_min := int(day_phase * 24.0 * 60.0) % (24 * 60)
	var h := total_min / 60
	var m := total_min % 60
	return "%02d:%02d" % [h, m]

func get_day() -> int:
	return day_idx

func is_night() -> bool:
	return _is_night()
