@tool
extends EditorPlugin

## 双语编辑器插件（Godot 4.7.1 适配）
## 编辑器界面显示为 "英文 (中文)"，中文取自官方 zh_Hans 翻译。
## 六层机制：
##   ① 把双语表注入引擎内建翻译域 godot.editor 并重排序到最前（内建中文兜底），
##      启动后创建的界面（对话框/右键菜单/检查器/F1 文档）创建时即双语；
##   ② 启动早期已烤死中文的静态界面（菜单栏/面板 Tab/底部面板），等界面建完后
##      从场景树根遍历，用反向映射（中文 → "英文 (中文)"）二次改写；
##   ③ 广播 NOTIFICATION_TRANSLATION_CHANGED，让 auto-translate 控件
##      （存英文原文、显示时才翻译）重新查询双语表；
##   ④ 监听 node_added，惰性创建的对话框（如 F1 搜索帮助）进树后延迟改写兜底；
##   ⑤ 检查器属性名：4.7.1 还没有属性名翻译系统，把官方 l10n 仓库的属性翻译
##      （data/prop_zh_hans.json）做成正向映射（英文 → "英文 (中文)"），只在
##      EditorInspector 子树内改写 EditorProperty.label / 枚举文本；
##   ⑥ 检查器分组大标题：EditorInspectorSection 的标题是引擎内部成员绘制的、
##      脚本改不到，扫描时给分组挂自绘覆盖层（section_bi_overlay.gd）盖住原生
##      英文标题写双语；每 40 帧幂等扫描兜住重建/晚设文字的时机问题。
## 数据：data/en_zh.json（编辑器 UI 词表）、data/prop_zh_hans.json（属性名）、
##       data/enum_zh.json（常用枚举值补充，手写）。
## 重新生成/关闭/回退：见本目录 README.md。

const DATA_PATH := "res://addons/bilingual_editor/data/en_zh.json"
const PROP_PATH := "res://addons/bilingual_editor/data/prop_zh_hans.json"
const ENUM_PATH := "res://addons/bilingual_editor/data/enum_zh.json"
const OVERLAY_SCRIPT := preload("res://addons/bilingual_editor/section_bi_overlay.gd")

var _ours: Translation
var _rev := {}  # 中文 -> "英文 (中文)"，改写已烤死中文的静态界面
var _revProp := {}  # 中文 -> 英文（属性词表反查，分组标题从中文 tooltip 还原英文）
var _fwd := {}  # 英文 -> "英文 (中文)"，检查器属性名/枚举值改写
var _ph: RegEx  # 匹配 %s/%d/%.2f 等格式占位符
var _suffix: RegEx  # 匹配 " (3)" / " (3/5)" 之类的计数后缀
# property|路径 解析时的别名：属性 id 与显示名差别大的（ao/heightmap 等）
const PATH_ALIAS := {
	"ao": "Ambient Occlusion",
	"heightmap": "Height",
	"sss": "Subsurf Scatter",
	"bent normal": "Bent Normal Map",
	"uv1": "UV1",
	"uv2": "UV2",
}
var _inspectors: Array = []  # 缓存的检查器实例，供周期扫描
var _sweepTick := 0
var _active := false


func _enter_tree() -> void:
	if OS.get_environment("BI_OFF") == "1":
		return  # 对比实验用：禁用插件全部行为
	_active = true
	_ph = RegEx.new()
	_ph.compile("%[0-9.+\\- #]*[sdfgxXouceEgG]")
	_suffix = RegEx.new()
	_suffix.compile(" \\((\\d+(/\\d+)?)\\)$")
	_inject()
	_late_retext.call_deferred()
	get_tree().node_added.connect(_on_node_added)
	set_process(true)


func _exit_tree() -> void:
	if not _active:
		return
	set_process(false)
	get_tree().node_added.disconnect(_on_node_added)
	_withdraw()


func _process(_delta: float) -> void:
	if not _active or _fwd.is_empty():
		return
	# 检查器重建属性行/惰性展开资源编辑器时，文字设置时机不定（可能晚于
	# node_added 的几帧窗口）。周期性对检查器子树做幂等扫描兜底，亚毫秒级。
	_sweepTick += 1
	if _sweepTick % 40 != 0:
		return
	if _inspectors.is_empty() or _sweepTick % 400 == 0:
		_inspectors = EditorInterface.get_base_control().find_children("*", "EditorInspector", true, false)
		for insp in EditorInterface.get_base_control().find_children("*", "EditorDebuggerInspector", true, false):
			_inspectors.append(insp)
	for insp in _inspectors:
		if is_instance_valid(insp):
			_walk(insp, true)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[双语编辑器] 找不到数据文件 " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		push_warning("[双语编辑器] 数据文件无效 " + path)
		return {}
	return parsed


func _compose(skey: String, zh: String) -> String:
	# 动态字符串（含 %s 等占位符）经 vformat 格式化：中文部分里的占位符
	# 换成 "…"，保证组合后的占位符总数与英文原文一致，否则 vformat 报错。
	var zh_part := zh
	if skey.contains("%"):
		zh_part = _neutralize_placeholders(zh)
	return skey + " (" + zh_part + ")"


func _inject() -> void:
	var data := _load_json(DATA_PATH)
	if data.is_empty():
		return
	if not TranslationServer.has_domain(StringName("godot.editor")):
		push_warning("[双语编辑器] 找不到 godot.editor 翻译域，本插件只适配 Godot 4.x 内建域结构")
		return
	var dom := TranslationServer.get_or_add_domain(StringName("godot.editor"))

	_ours = Translation.new()
	_ours.resource_name = "bilingual_en_zh"
	_ours.locale = "zh_Hans"

	var sep := String.chr(4)  # msgctxt 与 msgid 的内部分隔符
	var count := 0
	for key in data:
		var skey := String(key)
		var zh: String = data[key]
		if zh.is_empty() or zh == skey:
			continue
		var value := _compose(skey, zh)
		if skey.contains(sep):
			var idx := skey.find(sep)
			_ours.add_message(StringName(skey.substr(idx + 1)), StringName(value), StringName(skey.substr(0, idx)))
		else:
			_ours.add_message(StringName(skey), StringName(value))
		count += 1
		# 反向映射，供二次改写已烤死的界面文字；同中文多英文时取先出现的
		if not _rev.has(zh):
			_rev[zh] = value

	# 重排序：双语表放最前，内建中文随后兜底（同词条先命中先用）。
	# 若内建表此时还没装载（启动更晚），append 顺序天然让双语表在前，两种时序都成立。
	var builtins: Array = []
	for t in dom.get_translations():
		if String(t.get_locale()).begins_with("zh"):
			builtins.append(t)
	for t in builtins:
		dom.remove_translation(t)
	dom.add_translation(_ours)
	for t in builtins:
		dom.add_translation(t)

	# 正向映射（检查器属性名/枚举值）：属性词表 > UI 词表 > 手写枚举补充
	var props := _load_json(PROP_PATH)
	for key in props:
		var skey := String(key)
		var zh: String = props[key]
		if not zh.is_empty() and zh != skey and skey.length() >= 2:
			_fwd[skey] = _compose(skey, zh)
			if not _revProp.has(zh):
				_revProp[zh] = skey
	for key in data:
		var skey := String(key)
		var zh: String = data[key]
		if not zh.is_empty() and zh != skey and skey.length() >= 2 and not _fwd.has(skey):
			_fwd[skey] = _compose(skey, zh)
	var enums := _load_json(ENUM_PATH)
	for key in enums:
		var skey := String(key)
		var zh: String = enums[key]
		if not zh.is_empty() and zh != skey and skey.length() >= 2 and not _fwd.has(skey):
			_fwd[skey] = _compose(skey, zh)
			if not _revProp.has(zh):
				_revProp[zh] = skey

	print("[双语编辑器] 已注入 %d 条双语词条（godot.editor 域）+ %d 条属性名正向映射" % [count, _fwd.size()])


func _late_retext() -> void:
	# 等编辑器界面建完再改写，跑两遍兜住晚建的静态界面。
	# 两类烤死文字：①ET() 在创建时写入的中文（反向映射改写）
	# ②auto-translate 控件存英文原文、显示时才翻译但缓存了注入前的中文
	#  （广播 NOTIFICATION_TRANSLATION_CHANGED 强制重新查询双语表）。
	# 注意从场景树根遍历：编辑器对话框是独立 Window，不在 base_control 子树里。
	for wait in [60, 240]:
		for i in wait:
			await get_tree().process_frame
		var root := get_tree().root
		_walk(root, false)
		root.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	print("[双语编辑器] 静态界面双语化完成（反向映射 %d 条 + 正向映射 %d 条 + 翻译变更广播）" % [_rev.size(), _fwd.size()])


func _on_node_added(n: Node) -> void:
	# 惰性创建的对话框/菜单（如 F1 搜索帮助）与检查器重建的属性行，
	# 文字都可能烤死，新节点进树后分几帧多次改写兜底。
	call_deferred("_patch_later", n)


func _patch_later(n: Node) -> void:
	if not is_instance_valid(n):
		return
	# PopupMenu 不在这里补丁：下拉弹出窗正在显示时改条目会触发原生窗口重排
	# （疑似与"打开下拉闪黑"相关），它们的文字由启动遍历和周期扫描覆盖。
	if n is PopupMenu:
		return
	var in_insp := false
	var p := n.get_parent()
	while p != null:
		var pc := p.get_class()
		if pc == "EditorInspector" or pc == "EditorDebuggerInspector":
			in_insp = true
			break
		p = p.get_parent()
	_patch_node(n, in_insp)
	for wait in [1, 2, 6]:
		for i in wait:
			await get_tree().process_frame
		if not is_instance_valid(n):
			return
		_patch_node(n, in_insp)


func _walk(n: Node, in_insp: bool) -> void:
	var ins := in_insp or n.get_class() == "EditorInspector" or n.get_class() == "EditorDebuggerInspector"
	_patch_node(n, ins)
	for c in n.get_children():
		_walk(c, ins)


func _patch_node(n: Node, in_insp: bool = false) -> void:
	if n is Control:
		_patch_prop(n, "tooltip_text")
	if n is Button or n is Label or n is LinkButton:
		_patch_prop(n, "text")
	if n is Window:
		_patch_prop(n, "title")
		_patch_prop(n, "ok_button_text")
		_patch_prop(n, "cancel_button_text")
	if n is LineEdit:
		_patch_prop(n, "placeholder_text")
	elif n is PopupMenu:
		for i in n.get_item_count():
			var t: String = n.get_item_text(i)
			if _rev.has(t):
				n.set_item_text(i, _rev[t])
	elif n is TabBar:
		for i in n.get_tab_count():
			var t: String = n.get_tab_title(i)
			if _rev.has(t):
				n.set_tab_title(i, _rev[t])
	elif n is TabContainer:
		for i in n.get_tab_count():
			var t: String = n.get_tab_title(i)
			if _rev.has(t):
				n.set_tab_title(i, _rev[t])
	elif n is ItemList:
		for i in n.get_item_count():
			var t: String = n.get_item_text(i)
			if _rev.has(t):
				n.set_item_text(i, _rev[t])
	elif n is Tree:
		var root := (n as Tree).get_root()
		if root != null:
			_patch_tree_item(root, (n as Tree).columns)
	if in_insp:
		# 检查器专用：属性名/枚举文本正向改写成 "英文 (中文)"
		var lbl = n.get("label")
		if lbl is String:
			var b = _fwd_lookup(lbl)
			if b != null:
				n.set("label", b)
		if n is Control:
			var t2 = n.get("text")
			if t2 is String:
				var b2 = _fwd_lookup(t2)
				if b2 != null:
					n.set("text", b2)
		if n.get_class() == "EditorInspectorSection":
			_patch_section(n)


func _patch_section(sec: Node) -> void:
	# 分组大标题是引擎内部成员绘制的（label 属性为空、无 Label 子控件、无绑定方法），
	# 只能挂自绘覆盖层盖住原生英文标题写双语。标题从 tooltip 里反推：
	# 纯中文 → 反向映射；英文 → 正向映射；property|路径 → 解析末段逐词查表。
	var t = sec.get("tooltip_text")
	var title := ""
	if t is String:
		title = _section_bilingual(t)
	if title == "":
		return
	var ov: Control = null
	for c in sec.get_children():
		if c.name == "BiOverlay":
			ov = c
			break
	if ov == null:
		ov = OVERLAY_SCRIPT.new()
		ov.name = "BiOverlay"
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.set("cover_color", _panel_bg(sec))
		sec.add_child(ov)
		ov.top_level = true
		ov.global_position = sec.global_position
	# 右侧留出启用开关/改动计数区域，不能盖住交互控件；
	# 文字/尺寸只在变化时才写和重绘，避免周期扫描反复触发布局与重绘
	var target := Vector2(maxf(sec.size.x - 150.0, 120.0), 24.0)
	if ov.bi_text != title or ov.size != target:
		ov.bi_text = title
		ov.size = target
		ov.queue_redraw()


func _section_bilingual(t: String) -> String:
	# tooltip 是引擎 TTR 的结果：纯中文（内建直查）/"英文 (中文)"（命中我们的表）/property|路径
	if t == "":
		return ""
	if _rev.has(t):
		return _rev[t]
	if _revProp.has(t):
		return _fwd[_revProp[t]]
	if _fwd.has(t):
		return _fwd[t]
	if t.contains(" (") and not t.begins_with("property|"):
		return t  # 已经是双语成品，直接当覆盖层文字
	if t.begins_with("property|"):
		var seg := t.split("|")
		var pname := String(seg[seg.size() - 1]).split("/")[0]
		# 去掉 _enabled/_disabled 类后缀再查别名与词表（ao_enabled → ao → Ambient Occlusion）
		var bare := pname
		for suf in ["_enabled", "_disabled", "_show"]:
			if bare.ends_with(suf):
				bare = bare.trim_suffix(suf)
		if PATH_ALIAS.has(bare):
			var aliased: String = PATH_ALIAS[bare]
			if _fwd.has(aliased):
				return _fwd[aliased]
		var cur := pname.replace("_", " ").capitalize()
		for i in 4:
			if cur.length() < 3:
				return ""
			if _fwd.has(cur):
				return _fwd[cur]
			var sp := cur.rfind(" ")
			if sp < 0:
				return ""
			cur = cur.substr(0, sp)
	return ""


func _panel_bg(n: Node) -> Color:
	# 覆盖层遮底的底色：优先取所属检查器的 panel 背景色，回退编辑器 base_color
	var p := n
	while p != null:
		if p.get_class() == "EditorInspector":
			var sb = p.get_theme_stylebox("panel")
			if sb != null and sb is StyleBoxFlat:
				return (sb as StyleBoxFlat).bg_color
			break
		p = p.get_parent()
	var c = n.get_theme_color("base_color", "Editor")
	if c != null:
		return c
	return Color(0.12, 0.12, 0.12)


func _patch_prop(ctrl: Node, prop: String) -> void:
	var t = ctrl.get(prop)
	if t is String and _rev.has(t):
		ctrl.set(prop, _rev[t])


func _fwd_lookup(s: String):
	# 先精确匹配，再剥掉 " (3)"、" (3/5)" 这类计数后缀匹配主体
	if s.length() < 2:
		return null
	if _fwd.has(s):
		return _fwd[s]
	var m := _suffix.search(s)
	if m != null:
		var base := s.substr(0, m.get_start())
		if _fwd.has(base):
			return _fwd[base] + s.substr(m.get_start())
	return null


func _patch_tree_item(item: TreeItem, columns: int) -> void:
	for c in columns:
		var t := item.get_text(c)
		if _rev.has(t):
			item.set_text(c, _rev[t])
	var child := item.get_first_child()
	while child != null:
		_patch_tree_item(child, columns)
		child = child.get_next()


func _neutralize_placeholders(zh: String) -> String:
	# 把中文里的 vformat 占位符（%s/%.2f…）换成 "…"；%% 转义的字面百分号原样保留。
	var sentinel := String.chr(1)
	var s := zh.replace("%%", sentinel)
	var out := ""
	var last := 0
	for m in _ph.search_all(s):
		out += s.substr(last, m.get_start() - last) + "…"
		last = m.get_end()
	out += s.substr(last)
	return out.replace(sentinel, "%%")


func _withdraw() -> void:
	if _ours == null:
		return
	if TranslationServer.has_domain(StringName("godot.editor")):
		var dom := TranslationServer.get_or_add_domain(StringName("godot.editor"))
		dom.remove_translation(_ours)
	_ours = null
