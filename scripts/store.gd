extends Node3D

## 便利店：霓虹小店 + 收银员 + 货架
## 靠近按 F 打开商店面板（武器/涂装/血上限），金币消费闭环

signal shop_opened()
signal shop_closed()

const STORE_XZ := Vector2(145, -55)   # 出生点东侧 16m 街面空地（射线实测 y=5.95；原 120,-40 是街区屋顶）
const INTERACT_R := 5.0

const ITEMS := [
	{"key": "rifle",     "name": "步枪",       "price": 400,  "desc": "火力更猛，解锁武器栏第 2 格", "color": Color(1, 0.35, 0.8)},
	{"key": "shotgun",   "name": "霰弹枪",     "price": 500,  "desc": "近战大杀器，解锁武器栏第 3 格", "color": Color(1, 0.85, 0.25)},
	{"key": "alien",     "name": "外星涂装",   "price": 350,  "desc": "毒绿霓虹皮肤，解锁当前枪涂装", "color": Color(0.5, 1, 0.45)},
	{"key": "hp",        "name": "海姆立克装甲","price": 300,  "desc": "血上限 +50，可叠加 3 次", "color": Color(1, 0.25, 0.3)},
	{"key": "ammo",      "name": "备弹补给",   "price": 80,   "desc": "当前武器备弹 +30", "color": Color(0.4, 1, 0.5)},
]

var player: Node3D
var hud: Control
var _store: Node3D
var _ring: Area3D
var _near := false
var _panel: Control
var _inner: Panel
var _coins_lbl: Label
var _items_vbox: VBoxContainer
var _hp_bought := 0
var _bought := {}            # key -> true
var _close_btn: Button
var _arm := {}               # 二次确认中的商品 key -> true
const CONFIRM_KEYS := ["rifle", "shotgun", "alien", "hp"]

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	# 等两帧找 player
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		await get_tree().create_timer(1.0).timeout
		player = get_tree().get_first_node_in_group("player")
	hud = get_parent().get_node_or_null("HUD")
	add_to_group("shop_block_pause")
	_build_store()
	_build_panel()
	# 小地图标记
	var mm := get_parent().get_node_or_null("Minimap")
	if mm and mm.has_method("add_marker"):
		mm.add_marker("store", Vector3(STORE_XZ.x, 6.0, STORE_XZ.y), Color(0.2, 0.95, 1.0), "便利店")

func _build_store() -> void:
	_store = Node3D.new()
	_store.name = "便利店"
	add_child(_store)
	var pos := Vector3(STORE_XZ.x, _gy(), STORE_XZ.y)

	# 地基
	var base := MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	base.mesh.size = Vector3(14, 0.4, 12)
	base.position = pos + Vector3(0, 0.2, 0)
	base.material_override = _mat(Color(0.18, 0.18, 0.22))
	_store.add_child(base)

	# 主体（蓝白条纹小房子）
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(12, 4.2, 9)
	body.position = pos + Vector3(0, 2.1, 0)
	body.material_override = _mat(Color(0.92, 0.94, 0.98))
	_store.add_child(body)
	# 蓝条纹
	for i in range(3):
		var stripe := MeshInstance3D.new()
		stripe.mesh = BoxMesh.new()
		stripe.mesh.size = Vector3(12.1, 0.35, 0.15)
		stripe.position = pos + Vector3(0, 1.2 + i * 1.2, 4.58)
		stripe.material_override = _mat(Color(0.15, 0.45, 0.95))
		_store.add_child(stripe)

	# 招牌（发光）
	var sign := MeshInstance3D.new()
	sign.mesh = BoxMesh.new()
	sign.mesh.size = Vector3(10, 1.6, 0.3)
	sign.position = pos + Vector3(0, 5.3, 4.35)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.12, 0.28)
	sm.emission_enabled = true
	sm.emission = Color(0.2, 0.6, 1.0)
	sm.emission_energy_multiplier = 2.5
	sign.material_override = sm
	_store.add_child(sign)

	# 霓虹灯管（青/粉）
	var neon1 := MeshInstance3D.new()
	neon1.mesh = BoxMesh.new()
	neon1.mesh.size = Vector3(12.2, 0.15, 0.15)
	neon1.position = pos + Vector3(0, 4.5, 4.55)
	neon1.material_override = _glow(Color(0.2, 0.95, 1.0))
	_store.add_child(neon1)
	var neon2 := MeshInstance3D.new()
	neon2.mesh = BoxMesh.new()
	neon2.mesh.size = Vector3(0.15, 0.15, 9.2)
	neon2.position = pos + Vector3(-6.05, 4.5, 0)
	neon2.material_override = _glow(Color(1.0, 0.35, 0.8))
	_store.add_child(neon2)

	# 门口灯（夜景联动）
	var lamp := OmniLight3D.new()
	lamp.name = "store_lamp"
	lamp.light_color = Color(0.2, 0.9, 1.0)
	lamp.light_energy = 0.0                  # 昼夜系统接管（白天灭、晚上亮）
	lamp.set_meta("night_energy", 2.5)       # DayNight 以此为基准亮度
	lamp.omni_range = 14.0
	lamp.position = pos + Vector3(0, 4.5, 6.0)
	_store.add_child(lamp)

	# 收银员（站柜台后）
	var npc := MeshInstance3D.new()
	npc.mesh = BoxMesh.new()
	npc.mesh.size = Vector3(0.7, 1.7, 0.5)
	npc.position = pos + Vector3(0, 1.35, 3.0)
	npc.material_override = _mat(Color(0.15, 0.45, 0.95))
	_store.add_child(npc)
	var head := MeshInstance3D.new()
	head.mesh = SphereMesh.new()
	head.mesh.radius = 0.32
	head.mesh.height = 0.45
	head.position = pos + Vector3(0, 2.6, 3.0)
	head.material_override = _mat(Color(1.0, 0.85, 0.7))
	_store.add_child(head)

	# 柜台
	var counter := MeshInstance3D.new()
	counter.mesh = BoxMesh.new()
	counter.mesh.size = Vector3(8, 1.0, 1.2)
	counter.position = pos + Vector3(0, 0.9, 4.0)
	counter.material_override = _mat(Color(0.35, 0.28, 0.22))
	_store.add_child(counter)

	# 交互圈（quest_marker 风格：圈 + 进圈触发）
	_ring = Area3D.new()
	_ring.name = "store_ring"
	_ring.collision_layer = 0
	_ring.collision_mask = 1      # 玩家在 layer 1（原误写 2 导致进圈从不触发）
	_ring.position = pos + Vector3(0, 0.2, 5.0)
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = INTERACT_R
	cyl.height = 2.0
	col.shape = cyl
	_ring.add_child(col)
	_ring.body_entered.connect(_on_enter)
	_ring.body_exited.connect(_on_exit)
	_store.add_child(_ring)

func _gy() -> float:
	var from := Vector3(STORE_XZ.x, 20.0, STORE_XZ.y)
	var to := Vector3(STORE_XZ.x, -5.0, STORE_XZ.y)
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := sp.intersect_ray(q)
	return hit.position.y if hit else 6.0

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.2
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m

func _on_enter(body: Node3D) -> void:
	if body == player:
		_near = true
		_msg("按 F 进入便利店")

func _on_exit(body: Node3D) -> void:
	if body == player:
		_near = false
		if _panel and _panel.visible:
			_close_panel()

func _unhandled_input(event: InputEvent) -> void:
	if not _near or _panel == null:
		return
	if event.is_action_pressed("interact"):
		if not _panel.visible:
			_open_panel()
		else:
			_close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _panel.visible:
		_close_panel()
		get_viewport().set_input_as_handled()

func _msg(t: String) -> void:
	if hud and hud.has_method("_show_banner"):
		hud._show_banner(t, Color(0.2, 0.95, 1.0), 1.2)

func _open_panel() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout_panel()
	_refresh()
	if player and "input_locked" in player:
		player.input_locked = true
	emit_signal("shop_opened")

func _close_panel() -> void:
	_panel.visible = false
	_arm.clear()
	if player and "input_locked" in player:
		player.input_locked = false
	# 鼠标模式交还给暂停菜单的每帧管理（手柄模式不应强制捕获）
	emit_signal("shop_closed")

## PauseMenu 用来判断：商店面板开着时 ESC 只关商店，不弹暂停
func is_blocking_pause() -> bool:
	return _panel != null and _panel.visible

func _layout_panel() -> void:
	if _panel == null or not _panel.visible:
		return
	var s: Vector2 = get_viewport().get_visible_rect().size
	_panel.size = s
	var pw := 580.0
	var ph := 500.0
	_inner.position = Vector2(maxf(0.0, (s.x - pw) * 0.5), maxf(0.0, (s.y - ph) * 0.5))
	_inner.size = Vector2(pw, ph)

func _build_panel() -> void:
	# 全屏根 Control（直接挂 Node3D 也能上屏），内部面板按视口尺寸居中
	_panel = Control.new()
	_panel.name = "商店面板"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_panel.resized.connect(_layout_panel)

	# 半透明压暗
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.06, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(dim)

	# 居中内框
	_inner = Panel.new()
	_inner.add_theme_stylebox_override("panel",
		_panel_style(Color(0.04, 0.03, 0.10, 0.97), Color(1.0, 0.28, 0.62), 3, 16))
	_panel.add_child(_inner)

	# 标题
	var title := Label.new()
	title.text = "便 利 店  ·  MART"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.2, 0.9, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 16)
	title.size = Vector2(580, 44)
	_inner.add_child(title)

	# 金币显示
	_coins_lbl = Label.new()
	_coins_lbl.add_theme_font_size_override("font_size", 21)
	_coins_lbl.add_theme_color_override("font_color", Color(1, 0.83, 0.3))
	_coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_lbl.position = Vector2(0, 58)
	_coins_lbl.size = Vector2(556, 30)
	_inner.add_child(_coins_lbl)

	# 商品列表
	_items_vbox = VBoxContainer.new()
	_items_vbox.position = Vector2(24, 98)
	_items_vbox.size = Vector2(532, 330)
	_items_vbox.add_theme_constant_override("separation", 9)
	_inner.add_child(_items_vbox)
	for it in ITEMS:
		_items_vbox.add_child(_make_row(it))

	# 关闭按钮
	_close_btn = Button.new()
	_close_btn.text = "离开 (F / ESC)"
	_close_btn.add_theme_font_size_override("font_size", 19)
	_close_btn.add_theme_color_override("font_color", Color(0.88, 0.9, 1.0))
	_close_btn.position = Vector2(210, 444)
	_close_btn.size = Vector2(160, 40)
	_close_btn.pressed.connect(_close_panel)
	_inner.add_child(_close_btn)

func _panel_style(bg: Color, border: Color, bw: int, rad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(rad)
	s.shadow_color = Color(border, 0.4)
	s.shadow_size = 12
	return s

func _make_row(it: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(500, 56)
	row.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.09, 0.16, 0.8), Color(it.color, 0.5), 2, 8))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# 色块
	var swatch := ColorRect.new()
	swatch.color = it.color
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(swatch)

	# 名称+描述
	var name_lbl := Label.new()
	name_lbl.text = "%s  ·  %s" % [it.name, it.desc]
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)

	# 价格/状态按钮
	var btn := Button.new()
	btn.name = "buy_" + str(it.key)
	btn.custom_minimum_size = Vector2(110, 36)
	btn.add_theme_font_size_override("font_size", 17)
	btn.pressed.connect(_on_buy.bind(it.key))
	h.add_child(btn)

	return row

func _refresh() -> void:
	if player == null:
		return
	_coins_lbl.text = "金币 %d" % int(player.get("coins"))
	for row in _items_vbox.get_children():
		var btn := row.get_child(0).get_child(-1) as Button   # HBox 最后一个
		if btn == null:
			continue
		var key := btn.name.trim_prefix("buy_")
		var it: Dictionary = _item(key)
		var bought: bool = _bought.get(key, false)
		if key == "hp":
			btn.text = "确认购买？" if _arm.has(key) else "已购 %d/3  ·  %d" % [_hp_bought, int(it.price)]
			btn.disabled = _hp_bought >= 3
		elif key == "alien":
			var ws = player.get_node_or_null("WeaponSystem")
			btn.text = "确认购买？" if _arm.has(key) else ("已装备" if (ws and ws.alien_skin) else "购买 · %d" % int(it.price))
			btn.disabled = ws != null and ws.alien_skin
		elif key == "ammo":
			btn.text = "+%d 备弹 · %d" % [30, int(it.price)]
			btn.disabled = false
		else:
			if bought:
				btn.text = "已解锁"
			elif _arm.has(key):
				btn.text = "确认购买？"
			else:
				btn.text = "%d 金币" % int(it.price)
			btn.disabled = bought

func _item(key: String) -> Dictionary:
	for i in ITEMS:
		if i.key == key:
			return i
	return {}

## 购买按钮：贵重品先进入"确认"态，1.6 秒内再点一次才扣款
func _on_buy(key: String) -> void:
	if player == null:
		return
	if key in CONFIRM_KEYS and not _arm.has(key):
		_arm[key] = true
		_refresh()
		var btn := _find_buy_btn(key)
		if btn:
			btn.grab_focus()
		_msg("再点一次确认购买（1.6 秒内有效）")
		await get_tree().create_timer(1.6).timeout
		if _arm.has(key) and _panel.visible:
			_arm.erase(key)
			_refresh()
		return
	_arm.erase(key)
	_execute_buy(key)

func _find_buy_btn(key: String) -> Button:
	for row in _items_vbox.get_children():
		var btn := row.get_child(0).get_child(-1) as Button
		if btn and btn.name == "buy_" + key:
			return btn
	return null

func _execute_buy(key: String) -> void:
	var ws = player.get_node_or_null("WeaponSystem")
	var coins: int = int(player.get("coins"))
	var it: Dictionary = _item(key)
	if it.is_empty():
		return

	# 统一前置校验：可购状态 + 金币充足
	var sold_out := false
	match key:
		"rifle", "shotgun":
			sold_out = _bought.get(key, false)
		"alien":
			sold_out = ws != null and ws.alien_skin
		"hp":
			sold_out = _hp_bought >= 3
	if sold_out:
		_msg("该商品已拥有")
		_refresh()
		return
	if coins < int(it.price):
		_msg("金币不够！还差 %d" % (int(it.price) - coins))
		_refresh()
		return

	player.set("coins", coins - int(it.price))
	player.coin_collected.emit(player.coins)

	match key:
		"rifle", "shotgun":
			_bought[key] = true
			var wid := "rifle" if key == "rifle" else "shotgun"
			if ws:
				ws.unlock_weapon(wid)   # 解锁并补满备弹
			_msg("已解锁 %s！" % it.name)
		"alien":
			if ws:
				ws.alien_skin = true
				ws.call("_switch", ws.current, true)
			_bought[key] = true
			_msg("外星涂装已装备！毒绿霓虹上线")
		"hp":
			_hp_bought += 1
			player.max_hp = player.max_hp + 50.0
			player.hp = player.hp + 50.0
			if player.has_signal("hp_changed"):
				player.hp_changed.emit(player.hp, player.max_hp)
			_msg("血上限 +50！（%d/3）" % _hp_bought)
		"ammo":
			if ws:
				ws.reserves[ws.current] = min(ws.reserves[ws.current] + 30, 999)
				ws.ammo_changed.emit(ws.mags[ws.current], ws.reserves[ws.current])
			_msg("备弹 +30！")
	_refresh()
