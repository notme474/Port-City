extends Control

## 统计/成就面板：击杀/里程/金币/任务/撞人/通缉
## 挂 PauseMenu 下，ESC 或再次按"统计/成就"行关闭

var _panel: Control
var _rows := {}
var _visible := false

func _ready() -> void:
	visible = false
	_build()

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.size = Vector2(520, 420)
	_panel.position = Vector2(-260, -210)
	add_child(_panel)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.10, 0.94), Color(1, 0.85, 0.25), 3, 14))
	_panel.add_child(bg)

	var title := Label.new()
	title.text = "📊  统 计  /  成 就"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(520, 40)
	_panel.add_child(title)

	var items := [
		["kills",      "击杀数",       "0"],
		["distance",   "跑图里程",     "0 m"],
		["coins",      "累计金币",     "0"],
		["quests",     "任务完成",     "0/6"],
		["npc_hits",   "撞倒NPC",      "0"],
		["wanted_max", "最高通缉",     "0星"],
		["days",       "存活天数",     "1天"],
	]
	var y := 90
	for it in items:
		var lbl := Label.new()
		lbl.text = it[1]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		lbl.position = Vector2(60, y)
		lbl.size = Vector2(200, 28)
		_panel.add_child(lbl)
		var val := Label.new()
		val.name = it[0]
		val.text = it[2]
		val.add_theme_font_size_override("font_size", 20)
		val.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.position = Vector2(260, y)
		val.size = Vector2(200, 28)
		_panel.add_child(val)
		_rows[it[0]] = val
		y += 42

	var hint := Label.new()
	hint.text = "ESC 或再选一次返回"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 380)
	hint.size = Vector2(520, 24)
	_panel.add_child(hint)

func _style(bg: Color, border: Color, bw: int, rad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(rad)
	s.shadow_color = Color(border, 0.35)
	s.shadow_size = 14
	return s

func show_stats() -> void:
	visible = true
	_visible = true
	_refresh()

func hide_stats() -> void:
	visible = false
	_visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _visible and event.is_action_pressed("ui_cancel"):
		hide_stats()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	# 击杀/里程（player 累计）
	_set_stat("kills", str(int(p.get("_kills") if p.get("_kills") != null else 0)))
	var dist: float = p.get("_distance") if p.get("_distance") != null else 0.0
	_set_stat("distance", "%d m" % int(dist))
	_set_stat("coins", str(int(p.get("coins"))))
	# 任务完成数（quest + fun 三件套 + 老头）
	var done := 0
	var qs = get_tree().root.find_child("QuestSystem", true, false)
	# quest Stage.DONE=5（0 IDLE→5 DONE）
	if qs and int(qs.get("stage")) >= 5:
		done += 1
	var fn = get_tree().root.find_child("FunNpcs", true, false)
	if fn:
		# fun_npcs 的阶段变量是 fstage/bstage/cstage，DONE=2
		if (fn.get("fstage") as int) >= 2:
			done += 1
		if (fn.get("bstage") as int) >= 2:
			done += 1
		if (fn.get("cstage") as int) >= 2:
			done += 1
	# oldman CStage.DONE=5
	var om = get_tree().root.find_child("OldmanQuest", true, false)
	if om and (om.get("cstage") as int) >= 5:
		done += 1
	_set_stat("quests", "%d/6" % done)
	# 撞人
	var wp = get_tree().root.find_child("WantedPolice", true, false)
	_set_stat("npc_hits", str(int(wp.get("_npc_hits") if wp else 0)))
	_set_stat("wanted_max", "%d星" % int(wp.get("_wanted_max") if wp else 0))
	# 天数
	var dn = get_tree().root.find_child("DayNight", true, false)
	_set_stat("days", "%d天" % int(dn.day_idx if dn else 1))

func _set_stat(key: String, txt: String) -> void:
	if _rows.has(key):
		_rows[key].text = txt
