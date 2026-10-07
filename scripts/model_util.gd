class_name ModelUtil
extends RefCounted
## 动态模型贴地工具：所有运行时实例化的 GLB 统一用它把脚底对齐到地面，
## 避免各 GLB 原点不在脚底（granny -0.19 / mechcat -0.85 / oldman -3.36 等）导致陷地。

## 返回模型所有网格在【模型局部坐标系】下的最低 y（与模型自身缩放无关，为未缩放值）
static func aabb_min_y(inst: Node3D) -> float:
	var mn := 1e9
	var found := false
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			# 沿 mi → inst 的父节点链累乘变换（蒙皮模型常含 Armature 缩放层，
			# 直接用 mi.transform 会漏掉中间层导致 AABB 严重失真）
			var xform := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != inst:
				xform = (cur as Node3D).transform * xform
				cur = cur.get_parent()
			var box: AABB = xform * mi.mesh.get_aabb()
			mn = minf(mn, box.position.y)
			found = true
		for c in n.get_children():
			stack.append(c)
	return mn if found else 0.0

## 设置统一缩放 sc，并把模型抬高 -minY*sc，使其脚底落在父节点原点（ground_y=0）。
## ground_y：模型节点自身应处的地面高度（模型直接挂在地面节点上、而非"容器+模型子节点"时使用）。
static func snap_to_ground(mdl: Node3D, sc: float, ground_y := 0.0) -> void:
	var min_y := aabb_min_y(mdl)
	mdl.scale = Vector3.ONE * sc
	mdl.position.y = ground_y - min_y * sc
