shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 水面着色器（无贴图，适合 WebGL / Compatibility 导出）
//
// 水读成"水"靠三件事，缺一件就变成一张蓝纸：
//   1 一直在动的法线 —— 静水面在实时光照下是一块死掉的镜面；
//   2 菲涅耳的天空色 —— 掠射角越平越亮，这是水最像水的那个信号；
//   3 岸边要淡 —— 靠 `center`/`radius` 从径向距离现算出浅水带，
//      没有深度贴图时的替代品，浅滩因此有一圈发亮的边。
//
// 波形用三个不同频率/方向的解析正弦叠加，不用噪声纹理：零贴图是硬约束
// （Compatibility 渲染器下多一张纹理就多一次采样），而且正弦的前向差分
// 法线在远景不会像噪声那样糊成一片。代价是波纹有明显的方向性重复——
// 湖面上看不出来，溪那种细长的一眼里几乎看不见。

uniform vec4 deep_color    : source_color = vec4(0.075, 0.150, 0.175, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.230, 0.375, 0.340, 1.0);
uniform vec4 sky_color     : source_color = vec4(0.520, 0.660, 0.860, 1.0);
uniform vec4 dusk_tint     : source_color = vec4(0.190, 0.170, 0.230, 1.0);

uniform vec2 center = vec2(0.0, 0.0);
uniform float radius = 1.0;
// 指向太阳的单位向量（不是光的传播方向）。由 World3D 从 DirectionalLight3D 取。
uniform vec3 sun_dir = vec3(0.40, 0.70, 0.30);
uniform float ripple_scale  : hint_range(0.05, 3.0) = 0.55;
uniform float ripple_speed  : hint_range(0.0, 4.0) = 0.9;
uniform float ripple_amp    : hint_range(0.0, 4.0) = 0.60;
uniform float shore_inner   : hint_range(0.0, 1.0) = 0.42;
uniform float shore_outer   : hint_range(0.0, 1.5) = 1.02;
uniform float sky_mix       : hint_range(0.0, 1.0) = 0.42;
uniform float dusk_mix      : hint_range(0.0, 1.0) = 0.0;
uniform float spec_power    : hint_range(1.0, 256.0) = 84.0;

varying vec3 v_world;

// 三个方向/频率都不同的正弦。前向差分取法线（3 次求值而不是 5 次）：
// 差分是有偏的，但湖面上看不出来，而这一项每片元要跑三次。
float wave(vec2 p, float t) {
	float a = sin(p.x * 1.90 + p.y * 0.70 + t * 1.10);
	float b = sin(p.x * 0.60 - p.y * 1.45 + t * 0.80);
	float c = sin(p.x * -0.85 + p.y * 1.95 + t * 1.55);
	return (a + b * 0.62 + c * 0.34) / 1.96;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = v_world.xz;
	float t = TIME * ripple_speed;

	// 法线。e 取 0.4m：比它更小会在远处把波纹算成噪声，更大会把水面推平。
	//
	// `ripple_amp` 是**倾角**不是高度，三个正弦在 e 这一步上给出的 |Δh| 上限
	// 约 0.82，所以 amp 乘上去就是法线偏离竖直方向的角度：
	// 0.6 → 约 26°（平静的湖面），7.0 → 约 80°（整片锡纸）。
	// 第一版的 7.0 是照着"水面要一直在动"调的，而那个信号在 26° 上就已经
	// 足够——再往上只买到满屏的高光白斑和碎掉的倒影，读成泳池底而不是水。
	const float e = 0.40;
	vec2 p = w * ripple_scale;
	float h0 = wave(p, t);
	float hx = wave(p + vec2(e * ripple_scale, 0.0), t);
	float hz = wave(p + vec2(0.0, e * ripple_scale), t);
	vec3 n = normalize(vec3((h0 - hx) * ripple_amp, 1.0, (h0 - hz) * ripple_amp));

	// 浅水带：从碗心量起的径向距离。没有深度贴图，这是唯一能读出"近岸"的地方。
	float rr = length(w - center) / max(radius, 0.001);
	float shore = smoothstep(shore_inner, shore_outer, rr);

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, shore * 0.88);

	// 菲涅耳：越平视越像天。这是"这是水"最强的单一信号。
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sky_color.rgb, clamp(fres, 0.0, 1.0) * sky_mix);

	// 日头在波纹上的碎光。功率给高一点才有"一闪一闪"，
	// 低功率糊成一整片白斑，看着像水面上盖了张纸。
	vec3 view_dir = normalize(VIEW);
	vec3 refl = reflect(-normalize(sun_dir), n);
	float spec = pow(max(dot(refl, view_dir), 0.0), spec_power);
	col += vec3(1.0, 0.96, 0.86) * spec * 0.85;

	col = mix(col, col * dusk_tint.rgb * 2.4, dusk_mix);

	ALBEDO = col;
	NORMAL = n;
	ROUGHNESS = 0.09;
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
