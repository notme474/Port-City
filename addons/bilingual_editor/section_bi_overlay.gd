@tool
extends Control

# 检查器分组标题的双语覆盖层：EditorInspectorSection 的标题是引擎内部成员绘制的，
# 脚本改不到，所以在分组节点上挂一个自绘子控件，盖住原生英文标题、写双语。
# top_level 模式：脱离父容器的布局管理（容器重排/折叠/拖宽面板都碰不到它），
# 自己每帧钉在父节点的头部区域；由 bilingual_editor.gd 挂载并设置 bi_text 等字段。

var bi_text := ""
var cover_color := Color(0.11, 0.11, 0.12)
var text_color := Color(0.88, 0.88, 0.88)


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var p := get_parent()
	if p is Control and (p as Control).is_visible_in_tree():
		global_position = (p as Control).global_position


func _draw() -> void:
	if bi_text == "":
		return
	var f := get_theme_font("bold", "EditorFonts")
	if f == null:
		f = get_theme_default_font()
	var fs := get_theme_font_size("bold_size", "EditorFonts")
	if fs <= 0:
		fs = get_theme_default_font_size()
	var pad := 6.0
	var text_h := fs + pad
	var y := (size.y - text_h) * 0.5
	draw_rect(Rect2(Vector2(16, 0), Vector2(size.x - 16, size.y)), cover_color)
	draw_string(f, Vector2(22, y + fs - 2), bi_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 26, fs, text_color)
