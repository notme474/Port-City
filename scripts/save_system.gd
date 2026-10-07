extends Node

## 存档系统：金币/武器/涂装/血上限/任务进度/昼夜/通缉度
## 自动保存到 user://save.json；退出不丢进度

const SAVE_PATH := "user://save.json"

signal save_loaded()

var player: Node3D
var _save_timer := 0.0

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# 等武器系统挂上再恢复
	var ws = player.get_node_or_null("WeaponSystem")
	for i in range(30):
		if ws != null:
			break
		await get_tree().process_frame
		ws = player.get_node_or_null("WeaponSystem")
	_load()

func _process(delta: float) -> void:
	# 每 30 秒自动存档（防闪退丢进度）
	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()

func _collect() -> Dictionary:
	var d := {"version": 1, "timestamp": Time.get_unix_time_from_system()}
	if player:
		d["coins"] = int(player.get("coins"))
		d["hp"] = player.get("hp")
		d["max_hp"] = player.get("max_hp")
		d["pos"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	var ws = player.get_node_or_null("WeaponSystem") if player else null
	if ws:
		d["weapon_unlocked"] = ws.unlocked
		d["weapon_mags"] = ws.mags
		d["weapon_reserves"] = ws.reserves
		d["weapon_current"] = ws.current
		d["alien_skin"] = ws.alien_skin
	# 商店购买状态
	var store := get_parent().get_node_or_null("Store")
	if store:
		d["store_bought"] = store._bought
		d["store_hp_bought"] = store._hp_bought
	# 任务进度
	var qs := get_parent().get_node_or_null("QuestSystem")
	if qs:
		d["quest_stage"] = qs.get("stage")
	var fn := get_parent().get_node_or_null("FunNpcs")
	if fn:
		d["fun_stage_a"] = fn.get("fstage")
		d["fun_stage_b"] = fn.get("bstage")
		d["fun_stage_c"] = fn.get("cstage")
		d["fun_cans_collected"] = fn.get("cans_got")
	# 通缉度
	var wp := get_parent().get_node_or_null("WantedPolice")
	if wp:
		d["wanted_level"] = wp.get_stars()
	# 昼夜
	var dn := get_parent().get_node_or_null("DayNight")
	if dn:
		d["day_phase"] = dn.day_phase
		d["day_idx"] = dn.day_idx
	# 统计/成就
	var st := get_parent().get_node_or_null("StatsSystem")
	if st:
		d["stats_data"] = st.get_save()
	# 隐藏包裹
	var col := get_parent().get_node_or_null("Collectibles")
	if col:
		d["packages_data"] = col.get_save()
	# 竞速最佳成绩
	var race := get_parent().get_node_or_null("RaceSystem")
	if race:
		d["race_data"] = race.get_save()
	# 帮派据点清剿状态
	var camps := get_parent().get_node_or_null("GangCamps")
	if camps:
		d["camps_data"] = camps.get_save()
	return d

func save_game() -> void:
	var d := _collect()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if d.get("version", 0) != 1:
		return
	# 玩家属性
	player.set("coins", int(d.get("coins", 0)))
	player.coin_collected.emit(player.coins)
	var hp: float = d.get("hp", 100.0)
	var max_hp: float = d.get("max_hp", 100.0)
	player.max_hp = max_hp
	player.hp = minf(hp, max_hp)
	if player.has_signal("hp_changed"):
		player.hp_changed.emit(player.hp, player.max_hp)
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		player.global_position = Vector3(pos[0], pos[1], pos[2])
	# 武器
	var ws = player.get_node_or_null("WeaponSystem")
	if ws:
		var un: Array = d.get("weapon_unlocked", [true, false, false])
		for i in range(min(3, un.size())):
			ws.unlocked[i] = un[i]
		# mags/reserves 是 Array[int] 强类型，JSON 读回的是无类型 Array，必须逐元素赋值
		var mags: Array = d.get("weapon_mags", [])
		if mags.size() == 3:
			for i in 3:
				ws.mags[i] = int(mags[i])
		var res: Array = d.get("weapon_reserves", [])
		if res.size() == 3:
			for i in 3:
				ws.reserves[i] = int(res[i])
		ws.alien_skin = d.get("alien_skin", false)
		var cur: int = int(d.get("weapon_current", 0))
		ws.call("_switch", cur, true)
	# 商店
	var store := get_parent().get_node_or_null("Store")
	if store:
		store._bought = d.get("store_bought", {})
		store._hp_bought = int(d.get("store_hp_bought", 0))
	# 任务（只恢复阶段，不强制瞬移 NPC，让玩家自然走到触发点）
	var qs := get_parent().get_node_or_null("QuestSystem")
	if qs:
		qs.set("stage", d.get("quest_stage", 0))
	var fn := get_parent().get_node_or_null("FunNpcs")
	if fn:
		fn.set("fstage", d.get("fun_stage_a", 0))
		fn.set("bstage", d.get("fun_stage_b", 0))
		fn.set("cstage", d.get("fun_stage_c", 0))
	# 通缉度
	var wp := get_parent().get_node_or_null("WantedPolice")
	if wp:
		wp.set("_stars", clampi(int(d.get("wanted_level", 0)), 0, 5))
	# 昼夜
	var dn := get_parent().get_node_or_null("DayNight")
	if dn:
		var ph: float = d.get("day_phase", 0.03)
		# 深夜存档（0.30~0.78）恢复时快进到清晨：一进游戏黑灯瞎火体验太差
		if ph >= 0.30 and ph < 0.78:
			ph = 0.80
		dn.day_phase = ph
		dn.day_idx = int(d.get("day_idx", 1))
		# 立即应用一次避免闪白
		dn.call("_apply", true)
	# 统计/成就
	var st2 := get_parent().get_node_or_null("StatsSystem")
	if st2 and d.has("stats_data"):
		st2.set_save(d["stats_data"])
	# 隐藏包裹
	var col2 := get_parent().get_node_or_null("Collectibles")
	if col2 and d.has("packages_data"):
		col2.set_save(d["packages_data"])
	# 竞速最佳成绩
	var race2 := get_parent().get_node_or_null("RaceSystem")
	if race2 and d.has("race_data"):
		race2.set_save(d["race_data"])
	# 帮派据点清剿状态
	var camps2 := get_parent().get_node_or_null("GangCamps")
	if camps2 and d.has("camps_data"):
		camps2.set_save(d["camps_data"])
	emit_signal("save_loaded")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
