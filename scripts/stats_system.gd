extends Node
## 统计与成就系统：集中记录玩法数据，达成成就弹横幅并发金币奖励。
## 各玩法系统通过 add_stat() 上报；监听武器击杀/命中/开火与玩家金币信号。

signal achievement_unlocked(id: String, name: String, reward: int)

var player: Node
var stats := {
	"kills": 0, "hits": 0, "shots": 0, "headshots": 0,
	"packages": 0, "pickups": 0, "races_done": 0, "camps_cleared": 0,
	"best_jump_dist": 0.0, "coins_spent": 0, "play_minutes": 0.0,
}
var _unlocked: Array = []
var _t := 0.0

# id -> {名称, 描述, 统计键, 阈值, 奖金}
const ACH := [
	{"id": "first_blood", "n": "第一滴血", "d": "完成首次击杀", "k": "kills", "v": 1, "r": 500},
	{"id": "killer_10", "n": "街头打手", "d": "累计击杀 10", "k": "kills", "v": 10, "r": 1500},
	{"id": "killer_50", "n": "港城清道夫", "d": "累计击杀 50", "k": "kills", "v": 50, "r": 8000},
	{"id": "marksman", "n": "神枪手", "d": "累计命中 30 次", "k": "hits", "v": 30, "r": 1500},
	{"id": "pkg_half", "n": "寻宝者", "d": "找到 10 个隐藏包裹", "k": "packages", "v": 10, "r": 2000},
	{"id": "pkg_all", "n": "港城之主", "d": "找齐全部 20 个隐藏包裹", "k": "packages", "v": 20, "r": 100000},
	{"id": "racer", "n": "速度之王", "d": "完成一场检查点竞速", "k": "races_done", "v": 1, "r": 1500},
	{"id": "racer_3", "n": "竞速达人", "d": "完成 3 场竞速", "k": "races_done", "v": 3, "r": 5000},
	{"id": "stunt", "n": "特技飞人", "d": "单次飞车跳跃超过 50 米", "k": "best_jump_dist", "v": 50.0, "r": 2000},
	{"id": "camp_1", "n": "帮派克星", "d": "清除一个帮派据点", "k": "camps_cleared", "v": 1, "r": 2500},
	{"id": "camp_all", "n": "片区太平", "d": "清除全部 3 个帮派据点", "k": "camps_cleared", "v": 3, "r": 10000},
	{"id": "pickup_30", "n": "勤俭持家", "d": "拾取 30 个世界物资", "k": "pickups", "v": 30, "r": 2000},
	{"id": "rich", "n": "万元户", "d": "持有金币达到 10000", "k": "_coins", "v": 10000, "r": 3000},
]

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var ws := player.get_node_or_null("WeaponSystem")
	for i in 40:
		if ws != null and ws.has_signal("kill_confirmed"):
			break
		await get_tree().process_frame
		ws = player.get_node_or_null("WeaponSystem")
	if ws:
		if ws.has_signal("kill_confirmed"):
			ws.kill_confirmed.connect(func(_tn): add_stat("kills", 1))
		if ws.has_signal("hit_confirmed"):
			ws.hit_confirmed.connect(func(_dmg): add_stat("hits", 1))
		if ws.has_signal("shot_fired"):
			ws.shot_fired.connect(func(_w): add_stat("shots", 1))
	if player.has_signal("coin_collected"):
		player.coin_collected.connect(func(_c): _check_achievements())

func _process(delta: float) -> void:
	_t += delta
	if _t >= 60.0:
		_t = 0.0
		add_stat("play_minutes", 1.0)

## 上报数值统计（浮点键取 max，整型累加）
func add_stat(key: String, amount: float) -> void:
	if not stats.has(key):
		stats[key] = 0
	if key == "best_jump_dist":
		stats[key] = maxf(float(stats[key]), amount)
	else:
		stats[key] = float(stats[key]) + amount
	_check_achievements()

## 外部恢复存档
func set_save(d: Dictionary) -> void:
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	_unlocked = (d.get("achievements", []) as Array).duplicate()

func get_save() -> Dictionary:
	return {"stats": stats, "achievements": _unlocked}

func has(id: String) -> bool:
	return _unlocked.has(id)

func _check_achievements() -> void:
	for a in ACH:
		var id: String = a["id"]
		if _unlocked.has(id):
			continue
		var cur: float
		if a["k"] == "_coins":
			cur = float(player.coins) if player else 0.0
		else:
			cur = float(stats.get(a["k"], 0))
		if cur >= float(a["v"]):
			_unlock(a)

func _unlock(a: Dictionary) -> void:
	var id: String = a["id"]
	_unlocked.append(id)
	var reward: int = int(a["r"])
	if player and "coins" in player:
		player.coins += reward
		player.coin_collected.emit(player.coins)
	achievement_unlocked.emit(id, str(a["n"]), reward)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_banner"):
		hud.show_banner("成就解锁 · %s" % str(a["n"]), "%s   +%d 金币" % [str(a["d"]), reward])
