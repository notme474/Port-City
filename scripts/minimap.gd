extends CanvasLayer
## 小地图：右上角圆形地图，正上方相机实时渲染世界底图 + 玩家箭头 + 任务标记
## 玩家居中，底图随玩家移动滚动（角色一动就能看到地图变化）

const MAP_SIZE := 240.0        # 小地图像素直径
const VIEW_HEIGHT := 900.0     # 俯视相机高度（决定缩放/范围）
const VIEW_HALF := 600.0       # 相机正交半宽（世界单位，左右各看到 600m）

var player: Node3D
var markers := {}            # id -> {pos:Vector3, color:Color, label:String, icon:String}
var _icons := {}             # 图标缓存（assets/ui 下的 SVG，白色字形乘色使用）
var _focus_id := ""          # 任务专注：非空时只显示该标记，其余全部隐藏
var _hidden := {}            # 专注模式下被藏起来的标记（任务结束后恢复）

func _icon(nm: String) -> Texture2D:
	if not _icons.has(nm):
		_icons[nm] = load("res://assets/ui/%s.svg" % nm)
	return _icons[nm]
var _root: Control
var _vp: SubViewport
var _tex: TextureRect
var _draw: Control
var _cam: Camera3D

func _ready() -> void:
	layer = 10
	# 根容器：右上角
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.position = Vector2(-MAP_SIZE - 16, 16)
	_root.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	_root.size = Vector2(MAP_SIZE, MAP_SIZE)
	add_child(_root)

	# SubViewport + 俯视相机（渲染真实世界底图）
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(MAP_SIZE), int(MAP_SIZE))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.world_3d = get_viewport().world_3d   # 共享主场景 3D 世界，才能渲染城市
	_root.add_child(_vp)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_HALF * 2.0
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	_cam.current = true
	_cam.cull_mask = 0xFFFFFFFF  # 渲染所有层
	_vp.add_child(_cam)

	# 显示底图（圆形裁剪）
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.material = ShaderMaterial.new()
	(_tex.material as ShaderMaterial).shader = _circle_shader()
	_root.add_child(_tex)

	# 顶层绘制：玩家箭头 + 任务标记 + 边框
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_draw)
	_draw.draw.connect(_on_draw)

	# 找玩家（持续重试直到找到）
	call_deferred("_find_player")
	set_process(true)

func _circle_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
void fragment() {
	vec2 c = UV - 0.5;
	float d = length(c);
	if (d > 0.5) discard;
	COLOR = texture(TEXTURE, UV);
}
"""
	return s

func _find_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		player = p
		print("[Minimap] player found: ", player.name)

func add_marker(id: String, world_pos: Vector3, color := Color.RED, label := "", icon := "") -> void:
	# 专注模式下，非焦点标记一律进隐藏区，不显示（防止眼花缭乱）
	if _focus_id != "" and id != _focus_id:
		_hidden[id] = {"pos": world_pos, "color": color, "label": label, "icon": icon}
		return
	markers[id] = {"pos": world_pos, "color": color, "label": label, "icon": icon}
	_queue_redraw()

func remove_marker(id: String) -> void:
	markers.erase(id)
	_hidden.erase(id)
	_queue_redraw()

## 任务专注：只显示指定标记，其它全部暂时藏掉
func set_focus(id: String) -> void:
	_focus_id = id
	for k in markers.keys():
		if k != id:
			_hidden[k] = markers[k]
	markers.clear()
	if _hidden.has(id):
		markers[id] = _hidden[id]
		_hidden.erase(id)
	_queue_redraw()

## 退出任务：恢复所有被藏掉的标记
func clear_focus() -> void:
	_focus_id = ""
	for k in _hidden:
		markers[k] = _hidden[k]
	_hidden.clear()
	_queue_redraw()

func _queue_redraw() -> void:
	if _draw:
		_draw.queue_redraw()

func _process(_d: float) -> void:
	# 持续找玩家（防止首次没找到）
	if player == null:
		_find_player()
	# 相机跟随玩家正上方（不旋转，北朝上，更标准）
	if player and is_instance_valid(player):
		_cam.position = Vector3(player.global_position.x, VIEW_HEIGHT, player.global_position.z)
		_cam.rotation_degrees = Vector3(-90, 0, 0)
	_queue_redraw()

func _on_draw() -> void:
	var c := Vector2(MAP_SIZE * 0.5, MAP_SIZE * 0.5)
	if not player or not is_instance_valid(player):
		# 没找到玩家就只画边框
		_draw.draw_arc(c, MAP_SIZE * 0.5, 0, TAU, 40, Color(1.0, 0.3, 0.75, 0.9), 3)
		return
	# 玩家箭头（中心点）
	var yaw: float = player.rotation.y
	var fwd := Vector2(sin(yaw), cos(yaw))
	_draw.draw_polygon(
		PackedVector2Array([c, c + fwd * 14, c + Vector2(-fwd.y, fwd.x) * 6, c + Vector2(fwd.y, -fwd.x) * 6]),
		PackedColorArray([Color(0.2, 0.95, 1.0), Color(0.2, 0.95, 1.0), Color(0.2, 0.95, 1.0), Color(0.2, 0.95, 1.0)]))
	# 任务标记（相对玩家坐标，底图北朝上不旋转）
	for id in markers:
		var m = markers[id]
		var rel := Vector2(m.pos.x - player.global_position.x, m.pos.z - player.global_position.z)
		var px := rel * (MAP_SIZE * 0.5 / VIEW_HALF)
		if px.length() > MAP_SIZE * 0.5 - 10:
			px = px.normalized() * (MAP_SIZE * 0.5 - 10)
		var mp := c + px
		# 有图标画图标（白色字形乘任务色），没有画圆点
		var iname: String = m.get("icon", "")
		var tex: Texture2D = _icon(iname) if iname != "" else null
		if tex:
			_draw.draw_texture_rect(tex, Rect2(mp - Vector2(9, 9), Vector2(18, 18)), false, m.color)
		else:
			_draw.draw_circle(mp, 6, m.color)
		_draw.draw_arc(mp, 10, 0, TAU, 16, Color(1, 1, 1, 0.85), 2)
	# 边框
	_draw.draw_arc(c, MAP_SIZE * 0.5, 0, TAU, 40, Color(1.0, 0.3, 0.75, 0.9), 3)
