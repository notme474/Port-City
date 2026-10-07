extends RefCounted
## 程序化枪械音效合成：无外部音频资产，用白噪声爆音 + 低频正弦冲击生成
## AudioStreamWAV，在开火同一帧播放，从根上避免音效缺失/不同步。

const MIX_RATE := 22050

static var _streams: Dictionary = {}

## 生成（并缓存）一段枪声
## kind: pistol / rifle / shotgun / click
static func _stream(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var dur: float = 0.16
	var lp0: float = 0.55          # 噪声低通系数（越小越闷）
	var thump_hz: float = 75.0    # 低频冲击频率
	var thump_amp: float = 0.55
	var noise_amp: float = 0.75
	match kind:
		"rifle":
			dur = 0.11; lp0 = 0.75; thump_hz = 95.0; thump_amp = 0.4; noise_amp = 0.7
		"shotgun":
			dur = 0.32; lp0 = 0.4; thump_hz = 48.0; thump_amp = 0.9; noise_amp = 0.95
		"click":
			dur = 0.05; lp0 = 0.95; thump_hz = 1200.0; thump_amp = 0.12; noise_amp = 0.18
	var frames := int(dur * MIX_RATE)
	var ba := PackedByteArray()
	ba.resize(frames * 2)
	var lp := 0.0
	var phase := 0.0
	var dphase: float = TAU * thump_hz / MIX_RATE
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var decay: float = exp(-t * (26.0 if kind != "shotgun" else 16.0))
		var n: float = randf_range(-1.0, 1.0)
		lp += (n - lp) * lp0
		phase += dphase
		var s: float = n * noise_amp * decay * (1.0 - lp0 * 0.4)
		s += lp * noise_amp * decay * 0.9
		s += sin(phase) * thump_amp * exp(-t * 34.0)
		if kind == "click":
			s *= 0.5
		ba.encode_s16(i * 2, clampi(int(s * 26000.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = ba
	_streams[kind] = w
	return w

## 在世界坐标 pos 播放；parent 用于挂载（通常传玩家），播完自动释放
static func play_3d(parent: Node, pos: Vector3, kind: String, vol_db := -3.0) -> void:
	if parent == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(kind)
	p.global_position = pos
	p.volume_db = vol_db + randf_range(-1.5, 1.0)
	p.pitch_scale = randf_range(0.94, 1.06)
	p.unit_size = 6.0
	p.max_distance = 90.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	var free_p := func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	p.finished.connect(free_p)
	p.play()
	# 兜底：1.5s 后强制回收（重复 free 已做有效性判断）
	p.get_tree().create_timer(1.5).timeout.connect(free_p)
