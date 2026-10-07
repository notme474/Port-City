extends Node3D


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# Reduce background and sun brightness when using the Compatibility renderer;
		# this tries to roughly match the appearance of Forward+.
		# This compensates for the different color space and light rendering for lights with shadows enabled.
		$Sun.light_energy = 0.24
		$Sun.shadow_opacity = 0.85
		$Environment.environment.background_energy_multiplier = 0.25
	_load_systems()

## 动态加载世界系统（海洋/码头/恐龙岛）、小地图、任务系统
func _load_systems() -> void:
	# 世界系统
	var ws := Node3D.new()
	ws.name = "WorldSystem"
	ws.set_script(load("res://scripts/world_system.gd"))
	add_child(ws)
	# 小地图
	var mm := CanvasLayer.new()
	mm.name = "Minimap"
	mm.set_script(load("res://scripts/minimap.gd"))
	add_child(mm)
	# 任务系统（含警察）
	var qs := Node3D.new()
	qs.name = "QuestSystem"
	qs.set_script(load("res://scripts/quest_system.gd"))
	add_child(qs)
	# 交通局旋转车
	var tp := Node3D.new()
	tp.name = "TrafficPolice"
	tp.set_script(load("res://scripts/traffic_police.gd"))
	add_child(tp)
	# 下棋老头/BOSS/老头调节器
	var om := Node3D.new()
	om.name = "OldmanQuest"
	om.set_script(load("res://scripts/oldman_quest.gd"))
	add_child(om)
	# 抽象靶场（码头静态靶+市中心盘旋靶）
	var sr := Node3D.new()
	sr.name = "ShootingRange"
	sr.set_script(load("res://scripts/shooting_range.gd"))
	add_child(sr)
	# 拾取系统（步枪/霰弹枪/弹药）
	var pk := Node3D.new()
	pk.name = "PickupSystem"
	pk.set_script(load("res://scripts/pickup_system.gd"))
	add_child(pk)
	# 主城便民车（道路边 6 辆，靠近按 F 上车）
	var cc := Node3D.new()
	cc.name = "CityCars"
	cc.set_script(load("res://scripts/city_cars.gd"))
	add_child(cc)
	# 奇葩三件套：卖鱼强哥 / 广场舞之王 / 路灯外星人
	var fn := Node3D.new()
	fn.name = "FunNpcs"
	fn.set_script(load("res://scripts/fun_npcs.gd"))
	add_child(fn)
	# 暂停菜单（ESC/手柄START，键鼠-手柄切换，灵敏度/音量设置）
	var pm := CanvasLayer.new()
	pm.name = "PauseMenu"
	pm.set_script(load("res://scripts/pause_menu.gd"))
	add_child(pm)
	# 昼夜循环（太阳旋转/夜景灯光/月亮），放在最后确保所有灯已建
	var dn := Node3D.new()
	dn.name = "DayNight"
	dn.set_script(load("res://scripts/day_night.gd"))
	add_child(dn)
	# 便利店（武器/涂装/血上限，金币消费闭环）
	var st := Node3D.new()
	st.name = "Store"
	st.set_script(load("res://scripts/store.gd"))
	add_child(st)
	# 存档系统（自动保存/恢复，退出不丢）
	var sv := Node.new()
	sv.name = "SaveSystem"
	sv.set_script(load("res://scripts/save_system.gd"))
	add_child(sv)
	# 通缉度系统（撞人涨星→警车追→甩掉掉星）
	var wp := Node3D.new()
	wp.name = "WantedPolice"
	wp.set_script(load("res://scripts/wanted_police.gd"))
	add_child(wp)
	# 医院（死亡复活点，必须早于 DeathSystem）
	var hosp := Node3D.new()
	hosp.name = "Hospital"
	hosp.set_script(load("res://scripts/hospital.gd"))
	add_child(hosp)
	# 路边装饰车（StaticBody 盒碰撞，零物理开销）
	var props := Node3D.new()
	props.name = "CityProps"
	props.set_script(load("res://scripts/city_props.gd"))
	add_child(props)
	# 城市行人（layer 4，NPC 互不碰撞，沿道路散步，接入通缉撞人判定）
	var npcs := Node3D.new()
	npcs.name = "CityNpcs"
	npcs.set_script(load("res://scripts/city_npcs.gd"))
	add_child(npcs)
	# 高架地铁（纯观赏环线，玩家不可乘坐）
	var metro := Node3D.new()
	metro.name = "Metro"
	metro.set_script(load("res://scripts/metro.gd"))
	add_child(metro)
	# 死亡演出（红屏→死亡→黑屏→医院复活）
	var death := CanvasLayer.new()
	death.name = "DeathSystem"
	death.set_script(load("res://scripts/death_fx.gd"))
	add_child(death)
