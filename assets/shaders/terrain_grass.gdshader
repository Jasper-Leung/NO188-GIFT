shader_type spatial;
// Godot 4.6 cull_back 默认：cross.y<0 为正面。TerrainBuilder 建三角时
// 刻意翻转了缠绕顺序使 cross.y<0 成为正面，所以这里绝不能加
// cull_disabled / cull_front —— 加了反而会把地面剔掉。

// 地形草地质感程序化着色器（无贴图，适合 WebGL 导出）
// 目标：一整片 800m 见方的地面不能是死板的纯绿色块，要有低频色块、
// 中频草丛斑驳、高频麻点，再配一层会随距离淡出的法线扰动。
// 近处（桌面上 200m / Web 上 100m）由 GrassScatter 的实例化草皮卡片接管，
// 这层负责草环之外的地表质感。
// 所有噪声按世界米采样（v_world 是 MODEL_MATRIX 变换后的真实世界坐标），
// 不依赖 UV，因此和地形网格的疏密无关。

uniform vec4 ground_color      : source_color = vec4(0.360, 0.550, 0.240, 1.0);
uniform vec4 ground_dark       : source_color = vec4(0.240, 0.390, 0.160, 1.0);
uniform vec4 ground_dry        : source_color = vec4(0.470, 0.545, 0.245, 1.0);

uniform float mottle_scale     : hint_range(0.01, 4.0) = 0.35;   // 低频色块：每 ~3m 一个斑
uniform float clump_scale      : hint_range(0.01, 8.0) = 0.9;    // 中频草丛：每 ~1.1m 一簇
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.12;
uniform float detail_fade_near : hint_range(1.0, 200.0) = 6.0;
uniform float detail_fade_far  : hint_range(1.0, 200.0) = 20.0;
uniform float normal_strength  : hint_range(0.0, 1.0) = 0.15;
uniform float ao_strength      : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_base   : hint_range(0.0, 1.0) = 0.95;

varying vec3 v_world;
varying float v_view_dist;

// 与 asphalt.gdshader 逐字一致的噪声工具，lacunarity 同样取 2.02
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	float f = 1.0;
	v += a * vnoise(p);     f *= 2.02; a *= 0.5;
	v += a * vnoise(p * f); f *= 2.02; a *= 0.5;
	v += a * vnoise(p * f);
	return v;
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	v += a * vnoise(p);
	v += a * vnoise(p * 2.02);
	return v;
}

void vertex() {
	// MODEL_MATRIX 在这里已经含实例/模型变换，得到的是真实世界米
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view_dist = distance(v_world, CAMERA_POSITION_WORLD);
}

void fragment() {
	vec2 wp = v_world.xz;

	// 底色 -> 低频大色块
	float mottle = fbm2(wp * mottle_scale);
	vec3 col = mix(ground_color.rgb, ground_dark.rgb,
		smoothstep(0.40, 0.95, mottle) * 0.75);

	// 中频草丛斑驳：偏黄的一层，是"草原有变化"的主要来源
	float clump = fbm3(wp * clump_scale);
	col = mix(col, ground_dry.rgb, smoothstep(0.50, 0.95, clump) * 0.45);

	// 高频麻点，只在近处看得见
	float speck = fbm2(wp * 6.0);
	col = mix(col, ground_dark.rgb, smoothstep(0.55, 0.95, speck) * speckle_strength);

	// 顶点明暗。StandardMaterial3D 上的 vertex_color_use_as_albedo 是
	// BaseMaterial3D 专有标志，换成 ShaderMaterial 后静默失效，
	// 不在这里乘回去地形就会整体变亮（0.82~1.0 的压暗整个丢掉）。
	col *= COLOR.rgb;

	ALBEDO = col;
	ROUGHNESS = roughness_base;

	// 法线扰动必须随距离淡出，而且系数要比 asphalt 小一个量级。
	// asphalt 那套 fbm2(wp*11) + 差分放大 16.0 是给 13m 宽、4m 视高的路面调的；
	// 直接搬到 800m 地形上，地面会渲染成揉皱的锡纸/碎石而不是草。
	// 这里只求"脚边有一点起伏"，大尺度的立体感交给近处的草皮卡片。
	float detail_fade = 1.0 - smoothstep(detail_fade_near, detail_fade_far, v_view_dist);
	if (detail_fade > 0.001) {
		vec2 dp = wp * 9.0;
		float d0 = fbm2(dp);
		float dxn = fbm2(dp + vec2(0.35, 0.0));
		float dzn = fbm2(dp + vec2(0.0, 0.35));
		vec3 micro = vec3((d0 - dxn) * 5.0, 1.0, (d0 - dzn) * 5.0);
		NORMAL = normalize(mix(NORMAL, normalize(micro), normal_strength * detail_fade));
	}

	// 地形自身不投影（cast_shadow = OFF，见 TerrainBuilder），
	// 地面上的立体感全靠这一项 AO，别照抄 asphalt 里从 roughness 推的那个。
	float crevice = 1.0 - smoothstep(0.25, 0.75, clump);
	AO = mix(1.0, 1.0 - 0.45 * crevice, ao_strength);
	AO_LIGHT_AFFECT = 0.6;
}
