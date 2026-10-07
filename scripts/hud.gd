extends Control

## 霓虹 HUD：发光血/耐条、动态准星、换弹环、伤害飘屏、击杀横幅+连击、
## 受伤红屏、子弹时间蓝滤镜+扫描线、弹药面板、武器栏、拾取横幅（纯代码绘制）

# Vice City 调色板：热粉 / 迈阿密青 / 椰林金
const CYAN := Color(0.2, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const YELLOW := Color(1.0, 0.82, 0.3)
const RED := Color(1.0, 0.25, 0.3)
const CREAM := Color(1.0, 0.95, 0.85)   # VC 奶油白正文

var player: Node
var weapon: Node

# 状态
var _hp := 100.0
var _max_hp := 100.0
var _st := 100.0
var _max_st := 100.0
var _mag := 12
var _reserve := 30
var _wcolor := CYAN
var _spread := 8.0
var _spin := 0.0
var _hurt := 0.0
var _hp_hold_t := 0.0        # 受伤后血条保持全亮的剩余秒数
var _bar_alpha := 0.32       # 血/耐条当前不透明度（平时很淡，受伤后明显）
var _low_v := 0.0            # 低血量红边强度（随血量连续渐变，不硬切）
var _hit_t := 9.0
var _fire_t := 9.0
var _combo := 0
var _combo_t := 0.0
var _banner_t := 0.0
var _banner_dur := 0.0
var _banner_text := ""
var _banner_color := Color.WHITE
var _hint_t := 14.0

var _fx: Control
var _ammo_lbl: Label
var _ammo_sub: Label
var _reload_lbl: Label
var _combo_lbl: Label
var _dmg_root: Control
var _icons := {}   # 图标缓存（assets/ui 下的 SVG，白色字形乘色使用）
var _ind_n := 0    # 屏幕上存活的受击方向箭头数

func _icon(nm: String) -> Texture2D:
	if not _icons.has(nm):
		_icons[nm] = load("res://assets/ui/%s.svg" % nm)
	return _icons[nm]

func _ready() -> void:
	add_to_group("hud")
	call_deferred("_bind_player")
	_build()

## 公开横幅接口（区域发现/成就等系统调用）
func show_banner(title: String, sub := "") -> void:
	var txt := title if sub == "" else "%s   %s" % [title, sub]
	_show_banner(txt, MAGENTA, 3.0)

## 受击方向指示：v=(相对相机的右向分量, 前向分量)，屏幕边缘红箭头 0.7s 淡出
func show_damage_dir(v: Vector2) -> void:
	if v.length() < 0.05 or _ind_n >= 6:
		return
	var dn: Vector2 = v.normalized()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = vs * 0.5
	var radius: float = minf(vs.x, vs.y) * 0.36
	var l := Label.new()
	l.text = "▼"
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_color", RED)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.size = Vector2(46, 46)
	l.pivot_offset = Vector2(23, 23)
	var s := Vector2(dn.x, -dn.y)
	l.position = center + s * radius - Vector2(23, 23)
	l.rotation = atan2(s.y, s.x) - PI * 0.5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_ind_n += 1
	var tw := create_tween()
	tw.tween_property(l, "modulate", Color(1, 1, 1, 0), 0.7)
	tw.tween_callback(func() -> void:
		_ind_n -= 1
		l.queue_free())

# ---------- 搭建 ----------
func _build() -> void:
	# 所有绘制内容放一个全屏层（最先添加，在场景内金币节点之下）
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	move_child(_fx, 0)
	# 屏幕伤害飘字容器
	_dmg_root = Control.new()
	_dmg_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dmg_root)
	# 弹药数字
	_ammo_lbl = _mk_label(38, Color.WHITE)
	_ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_sub = _mk_label(18, Color(0.92, 0.88, 0.78))
	_ammo_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 换弹
	_reload_lbl = _mk_label(22, YELLOW)
	_reload_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 连击
	_combo_lbl = _mk_label(30, YELLOW)
	_combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

func _mk_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("line_spacing", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _on_coin_collected(coins):
	$Coins.text = str(coins)

func _bind_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_on_hp)
		player.stamina_changed.connect(_on_st)
		_on_hp(player.hp, player.max_hp)
		_on_st(player.stamina, player.max_stamina)
	# WeaponSystem 延迟挂到玩家，HUD 这边等几帧再绑定
	for i in range(10):
		weapon = player.get_node_or_null("WeaponSystem")
		if weapon != null:
			break
		await get_tree().process_frame
	if weapon == null:
		return
	weapon.ammo_changed.connect(_on_ammo)
	weapon.weapon_changed.connect(_on_weapon_changed)
	weapon.hit_confirmed.connect(_on_hit)
	weapon.kill_confirmed.connect(_on_kill)
	weapon.shot_fired.connect(func(_w): _fire_t = 0.0)
	if weapon.weapons.size() > 0:
		_on_weapon_changed(weapon.current, weapon.weapons[weapon.current], weapon.unlocked)
		_on_ammo(weapon.mags[weapon.current], weapon.reserves[weapon.current])

# ---------- 数据回调 ----------
func _on_hp(hp: float, max_hp: float) -> void:
	if hp < _hp:
		_hurt = 1.0
		_hp_hold_t = 4.0      # 受伤后血条全亮 4 秒，再缓缓淡下去
	_hp = hp
	_max_hp = max_hp

func _on_st(st: float, max_st: float) -> void:
	_st = st
	_max_st = max_st

func _on_ammo(mag: int, reserve: int) -> void:
	_mag = mag
	_reserve = reserve

func _on_weapon_changed(idx: int, w, _unlocked_arr) -> void:
	_wcolor = w.tracer_color
	_show_banner(w.display_name + " 已装备", w.tracer_color)
	if weapon:
		_on_ammo(weapon.mags[idx], weapon.reserves[idx])

func _on_hit(dmg: float) -> void:
	_hit_t = 0.0
	# 屏幕飘伤害数字
	var vp := get_viewport_rect().size
	var l := Label.new()
	l.text = "-%d" % int(dmg)
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", _wcolor)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.position = Vector2(vp.x * 0.5 + randf_range(10, 40), vp.y * 0.5 + randf_range(-30, -10))
	l.pivot_offset = Vector2(20, 14)
	_dmg_root.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.25)
	tw.tween_property(l, "scale", Vector2(1.3, 1.3), 0.15)
	tw.chain().tween_callback(l.queue_free)

func _on_kill(tname: String) -> void:
	_combo += 1
	_combo_t = 3.0
	_show_banner("击 杀  %s" % tname, Color(1, 0.6, 0.6), 1.2)

func _show_banner(text: String, color: Color, dur := 1.4) -> void:
	_banner_text = text
	_banner_color = color
	_banner_t = dur
	_banner_dur = dur

# ---------- 每帧 ----------
func _process(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta * 2.2)
	_hit_t += delta
	_fire_t += delta
	_spin += delta * (1.2 + 3.0 * exp(-_fire_t * 6.0))
	_banner_t = maxf(0.0, _banner_t - delta)
	_hint_t = maxf(0.0, _hint_t - delta)
	# 血条亮/淡：受伤 4 秒内全亮，之后平滑淡到 0.32（始终隐约可见，不突兀消失）
	_hp_hold_t = maxf(0.0, _hp_hold_t - delta)
	_bar_alpha = lerpf(_bar_alpha, 1.0 if _hp_hold_t > 0.0 else 0.32, delta * 5.0)
	# 低血量红边：血量 35%→12% 区间连续渐入，配合呼吸脉冲，绝不生硬整块红
	var frac := _hp / maxf(_max_hp, 1.0)
	var low_target := clampf((0.35 - frac) / (0.35 - 0.12), 0.0, 1.0)
	_low_v = lerpf(_low_v, low_target, delta * 3.0)
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0
	# 准星扩散脉冲
	var target_spread := 7.0 + (16.0 if _fire_t < 0.1 else 0.0)
	_spread = lerpf(_spread, target_spread, 0.35)
	_fx.queue_redraw()

# ---------- 绘制 ----------
func _draw_fx() -> void:
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	_draw_vignette(vp)
	_draw_bars(vp)
	_draw_coins_pill()
	_draw_ammo(vp)
	_draw_slots(vp)
	_draw_crosshair(c)
	_draw_reload(c)
	_draw_hitmarker(c)
	_draw_banner(vp)
	_draw_combo(c)
	_draw_hint(vp)
	_draw_nitro(vp)
	_draw_grenades(vp)

## 全屏边缘暗角 + 受伤红屏 + 低血量呼吸红边 + 子弹时间蓝调/扫描线
func _draw_vignette(vp: Vector2) -> void:
	var bt := Engine.time_scale < 0.9
	# 低血量红边强度：连续渐入值 _low_v × 呼吸脉冲（0.72~1.0），受伤瞬间的红闪叠加
	var pulse := 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.005)
	var ra := clampf(_hurt * 0.34 + _low_v * (0.28 + 0.22 * pulse), 0.0, 0.75)
	_edge_fx(vp, Color(1.0, 0.08, 0.12), ra)
	# 子弹时间
	if bt:
		_edge_fx(vp, Color(0.25, 0.6, 1.0), 0.4)
		_fx.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.3, 0.6, 1.0, 0.06), true)
		var line_col := Color(0.5, 0.8, 1.0, 0.07)
		var off := fmod(Time.get_ticks_msec() * 0.25, 8.0)
		for y in range(int(-8 + off), int(vp.y), 8):
			_fx.draw_line(Vector2(0, y), Vector2(vp.x, y), line_col, 1.0)

var _edge_tex: GradientTexture2D = null
var _edge_tex_sz := Vector2i(-1, -1)

## 屏幕四周边缘着色：径向渐变纹理（按屏幕半分辨率缓存，窗口尺寸变化才重建）。
## 中心全透明 → 四边淡入 → 四角最浓，配合整体 strength 调制，绝无生硬色块。
## （旧实现用 14 圈描边矩形、最内圈仍在屏幕外 134px，导致红边根本不可见。）
func _edge_fx(vp: Vector2, col: Color, strength: float) -> void:
	if strength <= 0.01:
		return
	var sz := Vector2i(maxi(8, int(vp.x * 0.5)), maxi(8, int(vp.y * 0.5)))
	if _edge_tex == null or _edge_tex_sz != sz:
		var g := Gradient.new()
		g.remove_point(1)
		g.remove_point(0)
		g.add_point(0.0, Color(1, 1, 1, 0.0))
		g.add_point(0.40, Color(1, 1, 1, 0.0))
		g.add_point(0.52, Color(1, 1, 1, 0.15))
		g.add_point(0.60, Color(1, 1, 1, 0.38))
		g.add_point(0.75, Color(1, 1, 1, 0.62))
		g.add_point(1.0, Color(1, 1, 1, 1.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = sz.x
		tex.height = sz.y
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 1.0)
		_edge_tex = tex
		_edge_tex_sz = sz
	_fx.draw_texture_rect(_edge_tex, Rect2(Vector2.ZERO, vp), false,
		Color(col.r, col.g, col.b, clampf(strength, 0.0, 1.0)))

## 左下霓虹血条/耐力条（受伤后高亮显示，平时淡而不抢镜）
func _draw_bars(vp: Vector2) -> void:
	var w := 280.0
	var x := 24.0
	var by := vp.y - 100.0
	var a := _bar_alpha
	_bar(Rect2(x, by, w, 20), _hp / maxf(_max_hp, 1.0), RED, "HP %d/%d" % [int(_hp), int(_max_hp)], a)
	_bar(Rect2(x, by + 30, w * 0.8, 12), _st / maxf(_max_st, 1.0), YELLOW, "", a)
	# 条尾状态图标（白色字形乘色）
	var heart := _icon("hp_icon")
	if heart:
		_fx.draw_texture_rect(heart, Rect2(x + w + 8, by - 3, 24, 24), false, Color(RED.r, RED.g, RED.b, RED.a * a))
	var bolt := _icon("stamina_icon")
	if bolt:
		_fx.draw_texture_rect(bolt, Rect2(x + w * 0.8 + 8, by + 25, 20, 20), false, Color(YELLOW.r, YELLOW.g, YELLOW.b, YELLOW.a * a))

func _bar(r: Rect2, frac: float, color: Color, txt: String, a := 1.0) -> void:
	_round(r, Color(0.03, 0.04, 0.07, 0.72 * a), 6.0, Color(color, 0.0), 0.0)
	if frac > 0.01:
		var fr := Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * frac, r.size.y - 4))
		_round(fr, Color(color.r, color.g, color.b, 0.95 * a), 4.0, Color(color, 0.8 * a), 2.0)
	if txt != "":
		_fx.draw_string(ThemeDB.fallback_font, r.position + Vector2(10, r.size.y * 0.72),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))

## 驾驶中右下氮气槽（Shift 激活时变粉高亮）
func _draw_nitro(vp: Vector2) -> void:
	if player == null:
		return
	var view2: Node = player.get_parent().get_node_or_null("View")
	if view2 == null:
		return
	var car: Object = view2.get("chase")
	if car == null:
		return
	var amt: float = clampf(float(car.get("_nitro")), 0.0, 1.0)
	var act: bool = bool(car.get("nitro_active"))
	var col := MAGENTA if act else CYAN
	var w := 240.0
	var r := Rect2(vp.x - w - 28.0, vp.y - 64.0, w, 14.0)
	_round(r, Color(0.03, 0.04, 0.07, 0.72), 6.0, Color(col, 0.9 if act else 0.25), 2.0 if act else 1.0)
	if amt > 0.01:
		var fr := Rect2(r.position + Vector2(2, 2), Vector2((w - 4.0) * amt, r.size.y - 4.0))
		_round(fr, Color(col.r, col.g, col.b, 0.95), 4.0, Color(col, 0.0), 0.0)
	_fx.draw_string(ThemeDB.fallback_font, r.position + Vector2(8, -4),
		"N2O", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col.r, col.g, col.b, 0.9))

## 右下角手雷剩余（G 投掷，无存货时暗红）
func _draw_grenades(vp: Vector2) -> void:
	if player == null:
		return
	var gs: Node = player.get_parent().get_node_or_null("GrenadeSystem")
	if gs == null:
		return
	var n: int = int(gs.get("grenades"))
	var col := Color(1.0, 0.55, 0.2) if n > 0 else Color(0.5, 0.12, 0.12)
	var txt := "手雷 [G]  x%d" % n
	_fx.draw_string(ThemeDB.fallback_font, Vector2(vp.x - 160.0, vp.y - 74.0),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)

func _round(r: Rect2, bg: Color, rad: float, border: Color, bw: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(rad))
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(bw))
		sb.shadow_color = Color(border, 0.8)
		sb.shadow_size = 6
	_fx.draw_style_box(sb, r)

## 金币霓虹胶囊
func _draw_coins_pill() -> void:
	_round(Rect2(40, 56, 215, 46), Color(0.05, 0.06, 0.1, 0.65), 12.0, YELLOW, 2.0)
	var coin := _icon("coin_icon")
	if coin:
		_fx.draw_texture_rect(coin, Rect2(47, 58, 42, 42), false, YELLOW)

## 右下弹药面板 + 武器栏
func _draw_ammo(vp: Vector2) -> void:
	var panel := Rect2(vp.x - 250, vp.y - 120, 226, 96)
	_round(panel, Color(0.04, 0.05, 0.09, 0.72), 10.0, Color(_wcolor, 0.9), 2.0)
	var abul := _icon("ammo_icon")
	if abul:
		_fx.draw_texture_rect(abul, Rect2(panel.position + Vector2(10, 36), Vector2(24, 24)), false, _wcolor)
	var low := _mag > 0 and _mag <= 3
	var mag_col := RED if low else _wcolor
	var pulse := 1.0 + (0.12 * sin(Time.get_ticks_msec() * 0.015) if low else 0.0)
	_ammo_lbl.text = "%d" % _mag
	_ammo_lbl.position = panel.position + Vector2(18, 14)
	_ammo_lbl.size = Vector2(panel.size.x - 36, 44)
	_ammo_lbl.add_theme_color_override("font_color", mag_col)
	_ammo_lbl.scale = Vector2.ONE * pulse
	_ammo_lbl.pivot_offset = Vector2(panel.size.x - 40, 22)
	_ammo_sub.text = "/  %d  备弹" % _reserve
	_ammo_sub.position = panel.position + Vector2(18, 58)
	_ammo_sub.size = Vector2(panel.size.x - 36, 24)
	# 换弹文字
	_reload_lbl.position = panel.position + Vector2(0, -30)
	_reload_lbl.size = Vector2(panel.size.x, 26)

func _draw_slots(vp: Vector2) -> void:
	var names := ["手枪", "步枪", "霰弹"]
	var icons := ["w_pistol", "w_rifle", "w_shotgun"]
	var cols := [CYAN, MAGENTA, YELLOW]
	var bw := 92.0
	var gap := 10.0
	var total := bw * 3 + gap * 2
	var x0 := vp.x - total - 24.0
	var y0 := vp.y - 162.0
	var alien: bool = weapon != null and weapon.get("alien_skin")
	for i in range(3):
		var unlocked: bool = weapon != null and weapon.unlocked[i]
		var active: bool = weapon != null and weapon.current == i
		var r := Rect2(x0 + i * (bw + gap), y0, bw, 34)
		var col: Color = cols[i] if unlocked else Color(0.3, 0.3, 0.35)
		_round(r, Color(col, 0.28 if active else 0.12), 7.0, Color(col, 1.0 if active else 0.4), 2.0 if active else 1.0)
		# 武器图标（外星涂装激活时当前格显示能量枪）
		var iname: String = icons[i]
		if alien and active:
			iname = "w_alien"
		var tex := _icon(iname)
		if tex:
			_fx.draw_texture_rect(tex, Rect2(r.position + Vector2(6, 5), Vector2(24, 24)), false, col)
		var txt := "%d %s" % [i + 1, names[i]] if unlocked else "%d 锁" % (i + 1)
		_fx.draw_string(ThemeDB.fallback_font, r.position + Vector2(32, 23),
			txt, HORIZONTAL_ALIGNMENT_CENTER, bw - 36, 15, col if unlocked else Color(0.55, 0.55, 0.6))

## 中心准星：旋转科技环 + 4 向刻度 + 中心点
func _draw_crosshair(c: Vector2) -> void:
	var col := _wcolor
	# 旋转两段弧
	var r := 15.0
	for k in range(2):
		var a0 := _spin + k * PI
		var pts := PackedVector2Array()
		for j in range(12):
			var a := a0 + float(j) / 11.0 * 1.1
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		_fx.draw_polyline(pts, Color(col, 0.5), 2.0, true)
	# 四刻度
	var g := _spread
	var L := 11.0
	var T := 2.5
	var dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for d in dirs:
		var p: Vector2 = c + d * g
		var a: Vector2 = p - d * L * 0.5
		var b: Vector2 = p + d * L * 0.5
		_fx.draw_line(a, b, Color.BLACK, T + 2.0, true)
		_fx.draw_line(a, b, col, T, true)
	# 中心点
	_fx.draw_circle(c, 2.0, col)

## 换弹进度环
func _draw_reload(c: Vector2) -> void:
	if weapon == null or float(weapon._reloading) <= 0.0:
		_reload_lbl.text = ""
		return
	var frac: float = 1.0 - float(weapon._reloading) / float(weapon.weapons[weapon.current].reload_time)
	_fx.draw_arc(c, 26.0, -PI / 2, -PI / 2 + TAU * frac, 36, YELLOW, 3.0, true)
	_reload_lbl.text = "换弹中 %d%%" % int(frac * 100)
	_reload_lbl.position = c + Vector2(-60, 34)
	_reload_lbl.size = Vector2(120, 26)

## 命中叉号（扩散+淡出）
func _draw_hitmarker(c: Vector2) -> void:
	if _hit_t > 0.35:
		return
	var f := _hit_t / 0.35
	var a := 1.0 - f
	var g := 8.0 + f * 10.0
	var col := Color(1, 1, 1, a)
	var ds := [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1)]
	for k in range(0, 4, 2):
		var p1: Vector2 = c + ds[k] * g
		var p2: Vector2 = c + ds[k + 1] * g
		_fx.draw_line(p1, p2, Color(0, 0, 0, a), 4.0, true)
		_fx.draw_line(p1, p2, col, 2.0, true)

## 击杀/拾取横幅（顶部中央，缩放进场）
func _draw_banner(vp: Vector2) -> void:
	if _banner_t <= 0.0:
		return
	var a := clampf(_banner_t / 0.3, 0.0, 1.0) if _banner_t < 1.0 else 1.0
	# 弹出动画：从生成时刻起 0.3s 内 1.25→1.0 收敛。
	# 旧公式 exp(-(1.4-_banner_t)*10) 在长横幅开局 exp(12)≈16万倍：字号 138 万导致
	# TextServer 缓存失败刷屏报错（hb_font null），底板矩形糊满全屏品红（整屏变紫）并卡顿。
	var elapsed: float = clampf(_banner_dur - _banner_t, 0.0, 2.0)
	var pop := 1.0 + 0.25 * exp(-elapsed * 10.0)
	var font := ThemeDB.fallback_font
	# get_string_size 第 3 个位置参数是换行宽度而非字号，字号是第 4 个（曾误传 34 导致横幅被压成 94px 宽、文字不可见）
	var w2 := font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 34).x + 60
	var r := Rect2(vp.x * 0.5 - w2 * 0.5 * pop, 120, w2 * pop, 52 * pop)
	_round(r, Color(0.03, 0.04, 0.08, 0.78 * a), 10.0, Color(_banner_color, a), 2.0)
	_fx.draw_string(font, Vector2(r.position.x + 30 * pop, r.position.y + 36 * pop),
		_banner_text, HORIZONTAL_ALIGNMENT_CENTER, (w2 - 60) * pop, 34 * pop,
		Color(_banner_color, a))

## 连击数（准星右侧）
func _draw_combo(c: Vector2) -> void:
	if _combo < 2:
		_combo_lbl.text = ""
		return
	var pop := 1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.02)
	_combo_lbl.text = "x%d 连击!" % _combo
	_combo_lbl.position = c + Vector2(34, -22)
	_combo_lbl.scale = Vector2.ONE * pop
	_combo_lbl.pivot_offset = Vector2.ZERO

## 操作提示（开局 14 秒后淡出）
func _draw_hint(vp: Vector2) -> void:
	if _hint_t <= 0.0:
		return
	var a := clampf(_hint_t / 2.0, 0.0, 0.85)
	var txt := "左键 射击    右键 瞄准    R 换弹    1/2/3 切枪    T 切视角    V 子弹时间    F 交互    ESC 暂停    鼠标 转镜头"
	var r := Rect2(vp.x * 0.5 - 360, vp.y - 52, 720, 34)
	_round(r, Color(0.03, 0.04, 0.08, a * 0.9), 8.0, Color(MAGENTA, a), 1.0)
	_fx.draw_string(ThemeDB.fallback_font, r.position + Vector2(0, 23), txt,
		HORIZONTAL_ALIGNMENT_CENTER, 720, 16, Color(CREAM, a))
