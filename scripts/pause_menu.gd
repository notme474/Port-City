extends CanvasLayer
## 霓虹暂停菜单：ESC / 手柄 START 暂停；可选键鼠/手柄；镜头灵敏度、音量设置。
## 面板上方有两只眼睛，瞳孔会实时锁定鼠标位置；键鼠模式游戏中锁定鼠标，暂停时释放。

const CYAN := Color(0.35, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.35, 0.8)
const YELLOW := Color(1.0, 0.85, 0.25)
const DIM := Color(0.02, 0.03, 0.07, 0.74)
const CFG_PATH := "user://settings.cfg"
const SENS_MIN := 0.05
const SENS_MAX := 0.60
const ROW_COUNT := 6

var _paused := false
var _kbm := true
var _sens := 0.25
var _vol := 1.0
var _sel := 0
var _dragging := -1
var _manual_lock := false   ## 玩家在菜单手动选过设备后，不再被设备噪声自动切换
var _last_auto_switch_ms := -100000 ## 上次自动切换设备的时刻（冷却用）
var _t := 0.0
var _look: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _blink_at := 2.2
var _blink_next_end := 0.0

var _panel: Control
var _stats: Control
var _font: Font

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_load_cfg()
	_build_ui()
	_build_stats()
	set_process(true)

func _build_stats() -> void:
	_stats = Control.new()
	# 必须全屏锚定：默认 size=0 会让 stats_panel 内部 PRESET_CENTER 锚到屏幕左上角
	_stats.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats.set_script(load("res://scripts/stats_panel.gd"))
	add_child(_stats)

func _toggle_stats() -> void:
	if _stats:
		if _stats.visible:
			_stats.hide_stats()
		else:
			_stats.show_stats()

# ---------- 对外接口（view.gd 读取） ----------
func is_kbm() -> bool:
	return _kbm

func get_sensitivity() -> float:
	return _sens

## 镜头脚本检测到真实鼠标移动时调用：非手动锁定手柄的情况下立即回到键鼠
func note_mouse_active() -> void:
	if not _manual_lock and not _kbm:
		_set_kbm(true)

# ---------- 搭建 ----------
func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_draw_all)
	_panel.gui_input.connect(_on_gui_input)
	add_child(_panel)

func _layout() -> Dictionary:
	var s: Vector2 = _panel.size
	var pw := 620.0
	var ph := 740.0
	var pr := Rect2((s.x - pw) * 0.5, (s.y - ph) * 0.5, pw, ph)
	var cx: float = pr.position.x + pw * 0.5
	var eyes: Array[Vector2] = [
		pr.position + Vector2(cx - pr.position.x - 95.0, 120.0),
		pr.position + Vector2(cx - pr.position.x + 95.0, 120.0),
	]
	var rows: Array[Rect2] = []
	var ry: float = pr.position.y + 250.0
	for i in ROW_COUNT:
		rows.append(Rect2(cx - 260.0, ry + i * 74.0, 520.0, 58.0))
	return {"panel": pr, "eyes": eyes, "rows": rows}

# ---------- 暂停 / 继续 ----------
func _pause() -> void:
	_paused = true
	_panel.visible = true
	_sel = 0
	_dragging = -1
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	_paused = false
	_panel.visible = false
	get_tree().paused = false
	_apply_mouse()

func _process(_delta: float) -> void:
	_t += _delta
	# 暂停时始终释放、游戏中键鼠锁定；窗口失焦时不抢锁定（否则会和系统
	# 焦点处理打架，鼠标反复锁定/释放导致镜头疯转）
	var focused: bool = get_window().has_focus()
	var want := Input.MOUSE_MODE_CAPTURED if (_kbm and not _paused and focused) else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	if _paused:
		_panel.queue_redraw()
		_smooth_eyes()

func _smooth_eyes() -> void:
	var lay := _layout()
	var eyes: Array[Vector2] = lay["eyes"]
	var mp: Vector2 = _panel.get_local_mouse_position()
	for i in eyes.size():
		var c: Vector2 = eyes[i]
		var target: Vector2 = (mp - c).limit_length(17.0)
		_look[i] = _look[i].lerp(target, 0.28)

# ---------- 输入：暂停切换 + 设备自动识别 + 菜单导航 ----------
func _unhandled_input(event: InputEvent) -> void:
	# 自动识别最后使用的设备。
	# 关键：摇杆信号【绝不】自动切手柄——摇杆会漂移，漂移会让镜头无限自转；
	# 只有手柄【按键】才算真手柄（按键不会自己触发）。
	# 真手柄玩家按任意手柄键即可，或在菜单手动选。键鼠则照常即切即回。
	if not _manual_lock:
		if event is InputEventJoypadButton and event.pressed:
			_auto_switch(false)
		elif event is InputEventKey and event.pressed:
			_auto_switch(true)
		elif event is InputEventMouseButton and event.pressed:
			_auto_switch(true)
		elif event is InputEventMouseMotion and event.relative.length() > 0.5:
			# 只要玩家真的在动鼠标，立刻回到键鼠（坏存档/手柄漂移也能自愈）
			_set_kbm(true)

	var pause_btn: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey and event.pressed \
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		pause_btn = true
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_START:
		pause_btn = true
	if pause_btn:
		if _paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return
	if not _paused:
		return
	# 键盘 / 手柄导航
	if event.is_action_pressed("ui_up"):
		_sel = wrapi(_sel - 1, 0, ROW_COUNT)
	elif event.is_action_pressed("ui_down"):
		_sel = wrapi(_sel + 1, 0, ROW_COUNT)
	elif event.is_action_pressed("ui_left"):
		_adjust(_sel, -1)
	elif event.is_action_pressed("ui_right"):
		_adjust(_sel, 1)
	elif event.is_action_pressed("ui_accept"):
		_activate(_sel)

func _on_gui_input(event: InputEvent) -> void:
	if not _paused:
		return
	var lay := _layout()
	var rows: Array[Rect2] = lay["rows"]
	if event is InputEventMouseMotion:
		if _dragging == 2 or _dragging == 3:
			var tr: Rect2 = _track_rect(rows[_dragging])
			_set_from_ratio(_dragging, tr, event.position.x)
			return
		_sel = _row_at(event.position, rows)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var idx: int = _row_at(event.position, rows)
		if idx < 0:
			return
		_sel = idx
		if event.pressed:
			if idx == 1:
				# 点中哪个设备盒就手动锁定哪个
				var boxes: Array[Rect2] = _mode_boxes(rows[1])
				if boxes[0].has_point(event.position):
					_manual_lock = true
					_set_kbm(true)
				elif boxes[1].has_point(event.position):
					_manual_lock = true
					_set_kbm(false)
			elif idx == 2 or idx == 3:
				var tr2: Rect2 = _track_rect(rows[idx]).grow(10.0)
				if tr2.has_point(event.position):
					_dragging = idx
					_set_from_ratio(idx, _track_rect(rows[idx]), event.position.x)
			else:
				_activate(idx)
		else:
			_dragging = -1

func _row_at(p: Vector2, rows: Array[Rect2]) -> int:
	for i in rows.size():
		var r: Rect2 = rows[i]
		if r.has_point(p):
			return i
	return -1

func _activate(idx: int) -> void:
	match idx:
		0:
			_resume()
		1:
			_set_kbm(not _kbm)
		4:
			_toggle_stats()
		5:
			get_tree().quit()

func _adjust(idx: int, dir: int) -> void:
	if idx == 2:
		_sens = clampf(_sens + 0.025 * dir, SENS_MIN, SENS_MAX)
		_save_cfg()
	elif idx == 3:
		_vol = clampf(_vol + 0.05 * dir, 0.0, 1.0)
		_apply_volume()
		_save_cfg()

func _set_from_ratio(row_idx: int, tr: Rect2, mx: float) -> void:
	var ratio: float = clampf((mx - tr.position.x) / tr.size.x, 0.0, 1.0)
	if row_idx == 2:
		_sens = lerpf(SENS_MIN, SENS_MAX, ratio)
	else:
		_vol = ratio
	_apply_volume()
	_save_cfg()

func _set_kbm(v: bool) -> void:
	if _kbm == v:
		return
	_kbm = v
	_apply_mouse()
	_save_cfg()

## 自动切换设备（键鼠↔手柄）：600ms 冷却。配合摇杆边沿触发，
## 防止噪声设备来回抢模式导致鼠标锁定状态反复切换、镜头疯转。
func _auto_switch(v: bool) -> void:
	if _kbm == v:
		return
	if Time.get_ticks_msec() - _last_auto_switch_ms < 600:
		return
	_last_auto_switch_ms = Time.get_ticks_msec()
	_set_kbm(v)

func _apply_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (_kbm and not _paused) else Input.MOUSE_MODE_VISIBLE

# ---------- 设置读写 ----------
func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		_kbm = int(cfg.get_value("input", "mode", 1)) == 1
		_sens = clampf(float(cfg.get_value("input", "sensitivity", 0.25)), SENS_MIN, SENS_MAX)
		_vol = clampf(float(cfg.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	_apply_volume()

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mode", 1 if _kbm else 0)
	cfg.set_value("input", "sensitivity", _sens)
	cfg.set_value("audio", "volume", _vol)
	cfg.save(CFG_PATH)

func _apply_volume() -> void:
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_mute(0, _vol <= 0.001)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_vol, 0.0001)))

# ---------- 行内几何 ----------
func _mode_boxes(row: Rect2) -> Array[Rect2]:
	var bw := 110.0
	var bh := 40.0
	var y: float = row.position.y + (row.size.y - bh) * 0.5
	var x1: float = row.end.x - 24.0 - bw * 2.0 - 8.0
	return [Rect2(x1, y, bw, bh), Rect2(x1 + bw + 8.0, y, bw, bh)]

func _track_rect(row: Rect2) -> Rect2:
	var w := 190.0
	var h := 8.0
	return Rect2(row.end.x - 24.0 - w, row.get_center().y - h * 0.5, w, h)

# ---------- 绘制 ----------
func _draw_all() -> void:
	var s: Vector2 = _panel.size
	# 背景压暗
	_panel.draw_rect(Rect2(Vector2.ZERO, s), DIM, true)
	# 扫描线
	var line_col := Color(CYAN.r, CYAN.g, CYAN.b, 0.025)
	var yy := 0
	while yy < int(s.y):
		_panel.draw_rect(Rect2(0, yy, s.x, 1), line_col, true)
		yy += 5

	var lay := _layout()
	var pr: Rect2 = lay["panel"]
	_draw_panel_frame(pr)
	_draw_eyes(lay["eyes"])
	_draw_title(pr)
	var rows: Array[Rect2] = lay["rows"]
	for i in rows.size():
		_draw_row(i, rows[i])
	# 底部操作提示
	var hint := "ESC / 手柄 START 继续      ↑↓ 选择      鼠标点击 / A 确认"
	_panel.draw_string(_font, Vector2(pr.position.x, pr.end.y - 24.0), hint,
		HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 17, Color(0.6, 0.7, 0.78))

func _draw_panel_frame(pr: Rect2) -> void:
	# 辉光底板
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(0.03, 0.05, 0.10, 0.96)
	glow.set_corner_radius_all(18)
	glow.set_border_width_all(2)
	glow.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.9)
	glow.shadow_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.45)
	glow.shadow_size = 26
	glow.content_margin_left = 0
	glow.content_margin_right = 0
	_panel.draw_style_box(glow, pr.grow(4))
	# 四角科技刻度
	var c := CYAN
	var L := 26.0
	var w := 3.0
	var lx: float = pr.position.x
	var rx2: float = pr.end.x
	var ty: float = pr.position.y
	var by2: float = pr.end.y
	# 左上
	_panel.draw_rect(Rect2(lx, ty, L, w), c, true)
	_panel.draw_rect(Rect2(lx, ty, w, L), c, true)
	# 右上
	_panel.draw_rect(Rect2(rx2 - L, ty, L, w), c, true)
	_panel.draw_rect(Rect2(rx2 - w, ty, w, L), c, true)
	# 左下
	_panel.draw_rect(Rect2(lx, by2 - w, L, w), c, true)
	_panel.draw_rect(Rect2(lx, by2 - L, w, L), c, true)
	# 右下
	_panel.draw_rect(Rect2(rx2 - L, by2 - w, L, w), c, true)
	_panel.draw_rect(Rect2(rx2 - w, by2 - L, w, L), c, true)

func _draw_title(pr: Rect2) -> void:
	var cx: float = pr.get_center().x
	_glow_text(Vector2(cx, pr.position.y + 188.0), "已 暂 停", 46, Color.WHITE, CYAN)
	_panel.draw_string(_font, Vector2(cx - 100.0, pr.position.y + 218.0), "PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER, 200.0, 20, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.85))

func _draw_row(i: int, row: Rect2) -> void:
	var sel: bool = i == _sel
	# 行底
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.10, 0.16, 0.85) if sel else Color(0.04, 0.06, 0.10, 0.7)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2 if sel else 1)
	sb.border_color = CYAN if sel else Color(0.25, 0.35, 0.45, 0.7)
	_panel.draw_style_box(sb, row)
	if sel:
		_panel.draw_rect(Rect2(row.position.x + 6, row.position.y + 10, 4, row.size.y - 20), MAGENTA, true)
		_panel.draw_rect(Rect2(row.end.x - 10, row.position.y + 10, 4, row.size.y - 20), MAGENTA, true)

	var tc: Color = Color.WHITE if sel else Color(0.62, 0.7, 0.78)
	match i:
		0:
			_center_text(row, "继 续 游 戏", 24, tc)
		1:
			_panel.draw_string(_font, row.position + Vector2(24, 38), "操控方式",
				HORIZONTAL_ALIGNMENT_LEFT, 200, 22, tc)
			_draw_mode_boxes(row)
		2:
			_panel.draw_string(_font, row.position + Vector2(24, 38), "镜头灵敏度",
				HORIZONTAL_ALIGNMENT_LEFT, 200, 22, tc)
			_draw_slider(row, (_sens - SENS_MIN) / (SENS_MAX - SENS_MIN))
		3:
			_panel.draw_string(_font, row.position + Vector2(24, 38), "主音量",
				HORIZONTAL_ALIGNMENT_LEFT, 200, 22, tc)
			_draw_slider(row, _vol)
		4:
			_center_text(row, "统 计 / 成 就", 24, Color(1, 0.85, 0.25) if sel else Color(0.7, 0.6, 0.3))
		5:
			_center_text(row, "退 出 游 戏", 24, Color(1, 0.5, 0.55) if sel else Color(0.7, 0.45, 0.5))

func _center_text(row: Rect2, t: String, sz: int, c: Color) -> void:
	_panel.draw_string(_font, Vector2(row.position.x, row.position.y + 38), t,
		HORIZONTAL_ALIGNMENT_CENTER, row.size.x, sz, c)

func _draw_mode_boxes(row: Rect2) -> void:
	var boxes: Array[Rect2] = _mode_boxes(row)
	var names: Array[String] = ["键鼠", "手柄"]
	for i in 2:
		var b: Rect2 = boxes[i]
		var on: bool = _kbm if i == 0 else not _kbm
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.22) if on else Color(0.05, 0.07, 0.11, 0.8)
		bs.set_corner_radius_all(8)
		bs.set_border_width_all(2)
		bs.border_color = CYAN if on else Color(0.3, 0.38, 0.48)
		_panel.draw_style_box(bs, b)
		_panel.draw_string(_font, Vector2(b.position.x, b.position.y + 27), names[i],
			HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 20, Color.WHITE if on else Color(0.6, 0.68, 0.75))

func _draw_slider(row: Rect2, ratio: float) -> void:
	var tr := _track_rect(row)
	_panel.draw_rect(tr.grow_individual(2.0, 5.0, 2.0, 5.0), Color(0.1, 0.14, 0.2, 0.9), true)
	var fill := Rect2(tr.position, Vector2(tr.size.x * ratio, tr.size.y))
	_panel.draw_rect(fill, CYAN, true)
	var knob_p: Vector2 = Vector2(tr.position.x + tr.size.x * ratio, tr.get_center().y)
	_panel.draw_circle(knob_p, 11.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.25))
	_panel.draw_circle(knob_p, 7.0, Color.WHITE)

# ---------- 两只锁定鼠标的眼睛 ----------
func _draw_eyes(eyes: Array[Vector2]) -> void:
	var blink: float = _blink_amount()
	for i in eyes.size():
		var c: Vector2 = eyes[i]
		# 眼眶
		_panel.draw_circle(c + Vector2(0, 6), 58.0, Color(0.01, 0.02, 0.05))
		_panel.draw_arc(c, 56.0, 0.0, TAU, 48,
			Color(CYAN.r, CYAN.g, CYAN.b, 0.85), 3.0, true)
		_panel.draw_arc(c, 62.0, 0.0, TAU, 48,
			Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.35), 2.0, true)
		var squash: float = 1.0 - blink * 0.94
		# 眼白
		_ellipse(c, 46.0, 46.0 * squash, Color(0.92, 0.97, 1.0))
		if squash > 0.18:
			var off: Vector2 = _look[i]
			# 青色虹膜 + 黑瞳孔 + 高光
			_panel.draw_circle(c + off, 21.0 * squash + 4.0, CYAN)
			_panel.draw_circle(c + off * 1.25, 10.5 * squash + 1.5, Color(0.02, 0.03, 0.06))
			if squash > 0.55:
				_panel.draw_circle(c + off - Vector2(5, 6), 3.2, Color(1, 1, 1, 0.9))
		if blink > 0.6:
			_panel.draw_line(c - Vector2(40, 0), c + Vector2(40, 0), Color(0.02, 0.05, 0.09), 5.0)

func _blink_amount() -> float:
	var b: float = _t - _blink_at
	if b < 0.0:
		return 0.0
	if b > 0.18:
		# 安排下一次眨眼
		if _blink_next_end < _t:
			_blink_at = _t + randf_range(2.2, 5.5)
			_blink_next_end = _blink_at
		return 0.0
	if b < 0.07:
		return b / 0.07
	return 1.0 - (b - 0.07) / 0.11

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 28
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_panel.draw_colored_polygon(pts, col)

func _glow_text(pos: Vector2, t: String, sz: int, col: Color, glow: Color) -> void:
	var p := Vector2(pos.x - 150.0, pos.y)
	for o in [Vector2(0, -2), Vector2(0, 2), Vector2(-2, 0), Vector2(2, 0)]:
		_panel.draw_string(_font, p + o, t, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz,
			Color(glow.r, glow.g, glow.b, 0.4))
	_panel.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_CENTER, 300.0, sz, col)
