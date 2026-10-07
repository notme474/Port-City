class_name WeaponData
extends Resource
## 武器数据（抽象霓虹枪）：一把枪的全部可调参数

@export var id := "pistol"
@export var display_name := "手枪"
@export var damage := 25.0          ## 单发弹丸伤害（贴脸基准值）
@export var fire_interval := 0.28   ## 射击间隔（秒）
@export var mag_size := 12          ## 弹匣容量
@export var max_reserve := 60       ## 备弹上限
@export var pellets := 1            ## 单次发射弹丸数（霰弹>1）
@export var spread_deg := 1.2       ## 扩散角（度）
@export var automatic := false      ## 是否全自动
@export var reload_time := 1.2      ## 换弹耗时（秒）
@export var two_handed := false     ## 动画用双手(2H)还是单手(1H)
@export var tracer_color := Color(0.3, 0.9, 1.0)  ## 曳光/发光色
@export var gun_kind := "pistol"    ## 几何拼枪类型: pistol/rifle/shotgun

# ---------- 弹道 / 伤害模型 ----------
@export var bullet_speed := 0.0     ## 弹丸初速（米/秒）；0 = 即时 hitscan
@export var gravity_scale := 1.0    ## 弹道下坠系数（乘武器系统的基础重力）
@export var falloff_range := 80.0   ## 伤害衰减到下限的距离（米）
@export var falloff_min := 0.6      ## 远距离最低伤害倍率
@export var recoil_pitch := 2.0     ## 单发上跳（度，可自动回位）
@export var recoil_yaw := 0.5       ## 单发水平抖动（度）
@export var shake := 0.02           ## 单发屏幕震动幅度（米）
@export var switch_time := 0.25     ## 切枪后开火锁定（秒，<=0.3 达标）
