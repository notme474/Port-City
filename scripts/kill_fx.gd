class_name KillFx
## 击杀特效：抽象几何碎片炸开 + 短暂顿帧（静态工具）

## 碎片爆炸：10 个发光小方块向四周飞散、缩小、消隐
static func explode(tree: SceneTree, pos: Vector3, color: Color) -> void:
	var root := tree.root
	for i in range(10):
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.12, 0.3)
		bm.size = Vector3.ONE * s
		shard.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		shard.material_override = mat
		root.add_child(shard)
		shard.global_position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(0, 0.5), randf_range(-0.3, 0.3))
		var dir := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		var tw := tree.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "global_position", shard.global_position + dir * randf_range(2.0, 4.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "scale", Vector3.ZERO, 0.65)
		tw.tween_property(shard, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.6)
		tw.chain().tween_callback(shard.queue_free)

## 顿帧：time_scale 瞬间压低再恢复（真实时间计时，不受慢动作影响）
static func hitstop(tree: SceneTree, duration := 0.12, scale := 0.05) -> void:
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	# 若期间用户开着子弹时间，恢复到手上的慢速而非 1.0
	var bt: float = float(tree.root.get_meta("bullet_time_scale", 1.0))
	Engine.time_scale = clampf(bt, 0.05, 1.0)
