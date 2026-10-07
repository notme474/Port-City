extends CanvasLayer
## Vice City 风格全屏后期：色彩分级（暗部青/亮部暖）+ 轻微色散 + 暗角 + 胶片颗粒
## layer=-2：位于 3D 画面之上、HUD(0) 与 PauseMenu(100) 之下，HUD 不受后期影响

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.055;
uniform float ca_amount : hint_range(0.0, 0.01) = 0.0020;
uniform float vignette_amount : hint_range(0.0, 0.8) = 0.30;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	// 色差（边缘轻微 RGB 分离，模拟老胶片镜头）
	vec2 off = d * ca_amount;
	vec3 c;
	c.r = texture(screen_tex, uv + off).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - off).b;
	// Miami teal-orange 分级：暗部染青，高光染暖
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 cool = vec3(0.86, 1.02, 1.14);
	vec3 warm = vec3(1.08, 1.0, 0.86);
	c *= mix(cool, warm, smoothstep(0.0, 1.0, lum));
	// 对比 + 饱和微调
	c = (c - 0.5) * 1.08 + 0.5;
	float l2 = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l2), c, 1.10);
	// 暗角
	float vig = smoothstep(0.9, 0.25, length(d * vec2(1.08, 0.92)));
	c *= mix(1.0 - vignette_amount, 1.0, vig);
	// 胶片颗粒（随时间变化）
	float g = hash21(uv * vec2(1600.0, 900.0) + fract(TIME * 3.0) * vec2(41.0, 23.0));
	c += (g - 0.5) * grain_amount;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

func _ready() -> void:
	layer = -2
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.z_index = -10
	add_child(rect)
