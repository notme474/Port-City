extends CanvasLayer

## 死亡演出：红屏压暗 → "死亡"大字 → 全黑 → 黑场中医院复活 → 黑场淡出
## 顺序固定、每段都有补间过渡，绝不硬切；复活时一并清除通缉与警车。

var _red: ColorRect
var _black: ColorRect
var _label: Label
var _tip: Label
var _playing := false

func _ready() -> void:
	layer = 40
	# 死亡 UI 不受暂停影响（玩家死亡瞬间任何输入态都能演完）
	process_mode = Node.PROCESS_MODE_ALWAYS

	_red = ColorRect.new()
	_red.color = Color(0.55, 0.0, 0.02, 0.0)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_red)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)

	_label = Label.new()
	_label.text = "死  亡"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 132)
	_label.add_theme_color_override("font_color", Color(1, 0.92, 0.92))
	_label.add_theme_color_override("font_outline_color", Color(0.25, 0, 0))
	_label.add_theme_constant_override("outline_size", 20)
	_label.add_theme_color_override("font_shadow_color", Color(0.4, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 0)
	_label.modulate = Color(1, 1, 1, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# 全屏布局完成后把缩放中心设为屏幕正中（_ready 时 size 尚未布局）
	await get_tree().process_frame
	_label.pivot_offset = _label.size * 0.5

	_tip = Label.new()
	_tip.text = "……您在医院苏醒"
	_tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.offset_top = 110
	_tip.add_theme_font_size_override("font_size", 30)
	_tip.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.0))
	_tip.modulate.a = 0.0
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)

func play_dead(player: Node) -> void:
	if _playing:
		return
	_playing = true
	# 1) 屏幕变红（0.45s 缓入）
	var tw := create_tween()
	tw.tween_property(_red, "color:a", 0.72, 0.45).set_ease(Tween.EASE_OUT)
	await tw.finished
	# 2) "死亡"大字带回弹地出现（0.5s）
	_label.scale = Vector2(0.6, 0.6)
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(_label, "modulate:a", 1.0, 0.3)
	tw2.tween_property(_label, "scale", Vector2(1.12, 1.12), 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw2.finished
	await get_tree().create_timer(0.9).timeout
	# 3) 屏幕全黑（0.6s）
	var tw3 := create_tween()
	tw3.tween_property(_black, "color:a", 1.0, 0.6)
	await tw3.finished
	# 4) 黑场保护中完成复活（玩家完全看不见传送）
	_respawn(player)
	await get_tree().create_timer(0.55).timeout
	# 红幕与大字在黑幕后收掉
	_red.color.a = 0.0
	_label.modulate.a = 0.0
	_label.scale = Vector2(0.6, 0.6)
	# 苏醒提示
	var tw_t := create_tween()
	tw_t.tween_property(_tip, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(0.9).timeout
	# 5) 黑场淡出，玩家已站在医院门口
	var tw4 := create_tween()
	tw4.set_parallel(true)
	tw4.tween_property(_black, "color:a", 0.0, 0.9).set_ease(Tween.EASE_IN_OUT)
	tw4.tween_property(_tip, "modulate:a", 0.0, 0.9)
	await tw4.finished
	_playing = false

## 黑场中复活：满血 + 传医院 + 解除驾驶 + 清空通缉
func _respawn(player: Node) -> void:
	# 若死亡时正在开车，先安全下车（恢复步行相机/碰撞），位置随后被复活点覆盖
	var cc := get_parent().get_node_or_null("CityCars")
	if cc:
		var mgr := cc.get_node_or_null("CityCarManager")
		if mgr and mgr.get("_driving") != null:
			mgr.call("_exit_vehicle")
	# 复活位置：医院门前；医院系统缺失时兜底回出生点
	var pos := Vector3(130, 6.15, -60)
	var hosp := get_parent().get_node_or_null("Hospital")
	if hosp and hosp.has_method("get_respawn"):
		pos = hosp.get_respawn()
	if player.has_method("revive_at"):
		player.revive_at(pos)
	else:
		player.global_position = pos
	# 死亡一笔勾销：清通缉星、撤警车
	var wp := get_parent().get_node_or_null("WantedPolice")
	if wp:
		if wp.has_method("_clear_police"):
			wp.call("_clear_police")
		wp.set("_stars", 0)
