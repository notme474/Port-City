class_name WeaponData
extends Resource
## 武器数据（抽象霓虹枪）：一把枪的全部可调参数

@export var id := "pistol"
@export var display_name := "手枪"
@export var damage := 25.0          ## 单发弹丸伤害
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
