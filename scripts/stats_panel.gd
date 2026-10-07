extends CanvasLayer
## 战绩与成就面板（B 键开关）。仿 GTA 手机风格，不暂停游戏但锁定玩家输入。
## 数据全部读自 StatsSystem；成就解锁状态以 stats.has(id) 为准。

var _sys: Node
var player: Node
var _open := false

var _root: Control
var _stats_box: VBoxContainer
var _ach_box: VBoxContainer

func _ready() -> void:
	layer = 20
	_register_input()
	_sys = get_parent().get_node_or_null("StatsSystem")
	_build()
	_root.visible = false

func _register_input() -> void:
	if not InputMap.has_action("stats_panel"):
		InputMap.add_action("stats_panel")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_B
	InputMap.action_add_event("stats_panel", ev)

var _rt := 0.0

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("stats_panel"):
		_toggle()
	if _open:
		_rt += delta
		if _rt >= 0.25:
			_rt = 0.0
			_refresh_stats()   # 金币等定时刷新

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(940, 660)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.1, 0.15, 0.97)
	pstyle.border_color = Color(0.95, 0.72, 0.2)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(10)
	pstyle.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", pstyle)
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := Label.new()
	title.text = "港城战绩"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.82, 0.3))
	col.add_child(title)

	var hint := Label.new()
	hint.text = "按 B 关闭"
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	col.add_child(hint)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(hb)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	var st_title := Label.new()
	st_title.text = "— 数据 —"
	st_title.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
	left.add_child(st_title)
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 6)
	left.add_child(_stats_box)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var ac_title := Label.new()
	ac_title.text = "— 成就 —"
	ac_title.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
	right.add_child(ac_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_ach_box = VBoxContainer.new()
	_ach_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_box.add_theme_constant_override("separation", 5)
	scroll.add_child(_ach_box)

	_refresh_stats()
	_refresh_achievements()

func _toggle() -> void:
	_open = not _open
	_root.visible = _open
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player and "input_locked" in player:
		player.input_locked = _open
	if _open:
		_refresh_stats()
		_refresh_achievements()

func _add_stat_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	_stats_box.add_child(l)

func _refresh_stats() -> void:
	if _sys == null:
		return
	var st: Dictionary = _sys.stats
	var coins := 0
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player and "coins" in player:
		coins = int(player.coins)
	var shots: int = int(st.get("shots", 0))
	var hitsv: int = int(st.get("hits", 0))
	var acc := 0.0
	if shots > 0:
		acc = float(hitsv) / float(shots) * 100.0
	for c in _stats_box.get_children():
		c.queue_free()
	_add_stat_row("金币：%d" % coins)
	_add_stat_row("击杀：%d" % int(st.get("kills", 0)))
	_add_stat_row("命中率：%.0f%%（%d/%d 发）" % [acc, hitsv, shots])
	_add_stat_row("爆头：%d" % int(st.get("headshots", 0)))
	_add_stat_row("隐藏包裹：%d / 20" % int(st.get("packages", 0)))
	_add_stat_row("世界物资拾取：%d" % int(st.get("pickups", 0)))
	_add_stat_row("竞速完成：%d 场" % int(st.get("races_done", 0)))
	_add_stat_row("帮派据点：%d / 3 已清剿" % int(st.get("camps_cleared", 0)))
	_add_stat_row("最远特技跳跃：%.1f m" % float(st.get("best_jump_dist", 0.0)))
	_add_stat_row("游玩时长：%.0f 分钟" % float(st.get("play_minutes", 0.0)))

func _refresh_achievements() -> void:
	if _sys == null:
		return
	var st: Dictionary = _sys.stats
	var coins := 0
	if player and "coins" in player:
		coins = int(player.coins)
	for c in _ach_box.get_children():
		c.queue_free()
	for a in _sys.ACH:
		var got: bool = _sys.has(str(a["id"]))
		var cur: float
		if str(a["k"]) == "_coins":
			cur = float(coins)
		else:
			cur = float(st.get(a["k"], 0))
		var target: float = float(a["v"])
		var l := Label.new()
		l.text = "%s %s — %s（%s/%s）  +%d" % [
			"[已达成]" if got else "[未达成]", str(a["n"]), str(a["d"]),
			_fmt(cur), _fmt(target), int(a["r"])]
		l.add_theme_font_size_override("font_size", 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if got:
			l.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		else:
			l.add_theme_color_override("font_color", Color(0.62, 0.64, 0.7))
		_ach_box.add_child(l)

func _fmt(v: float) -> String:
	if v == float(int(v)):
		return str(int(v))
	return "%.1f" % v
