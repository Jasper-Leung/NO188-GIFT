shader_type spatial;
// Godot 4.6 cull_back 默认：cross.y<0 为正面。RoadBuilder 逐三角形
// 强制 cross.y<0，所以默认 cull_back 即可，无需 cull_disabled。

// 沥青路面程序化着色器（无贴图，适合 WebGL 导出）
// UV.x: 横向 0..1（覆盖路面+路肩全宽）  UV.y: 沿路距离 / tile_size
// v_world = (横向米数, 沿路米数)，噪声全部按世界尺度采样

uniform vec4 asphalt_color     : source_color = vec4(0.168, 0.170, 0.178, 1.0);
uniform vec4 grain_dark_color  : source_color = vec4(0.068, 0.068, 0.074, 1.0);
uniform vec4 dirt_color        : source_color = vec4(0.300, 0.256, 0.184, 1.0);
uniform vec4 edge_line_color   : source_color = vec4(0.900, 0.900, 0.858, 1.0);
uniform vec4 center_line_color : source_color = vec4(0.928, 0.928, 0.898, 1.0);

uniform float road_half_width  : hint_range(1.0, 200.0) = 4.0;
uniform float total_half_width : hint_range(2.0, 200.0) = 6.5;
uniform float total_width      : hint_range(2.0, 400.0) = 13.0;
uniform float tile_size        : hint_range(1.0, 200.0) = 16.0;
uniform float roughness_base   : hint_range(0.0, 1.0) = 0.85;
uniform float plaza_mode       : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_world;

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
	v_world = vec2((UV.x - 0.5) * total_width, UV.y * tile_size);
}

void fragment() {
	float lateral = v_world.x;   // 横向米数，0 = 路面中心
	float along   = v_world.y;   // 沿路米数
	float edge    = abs(lateral);
	vec2 wp = vec2(lateral, along);

	// 沥青基底：骨料颗粒 + 中频斑驳 + 低频大块色差
	float grain  = pow(fbm3(wp * 9.0), 1.55);
	float mottle = fbm3(wp * 1.4 + vec2(3.1, 7.7));
	float large  = fbm2(wp * 0.22 + vec2(11.0, 5.0));

	vec3 col = asphalt_color.rgb;
	col = mix(col, grain_dark_color.rgb, grain * 0.6);
	col *= 0.80 + 0.40 * mottle;
	col *= 0.88 + 0.28 * large;

	// 轮胎带：每车道中心两侧各一条黑色胎痕（橡胶沉积）
	float lane = road_half_width * 0.5;
	float tracks = 0.0;
	if (plaza_mode < 0.5) {
		for (int s = -1; s <= 1; s += 2) {
			for (int w = -1; w <= 1; w += 2) {
				float cx = float(s) * lane + float(w) * 0.62;
				tracks = max(tracks, 1.0 - smoothstep(0.24, 0.44, abs(lateral - cx)));
			}
		}
		tracks *= 0.4 + 0.6 * vnoise(vec2(along * 0.22, 3.7));
		col *= 1.0 - 0.34 * tracks;
	}

	// 路缘起灰：靠近路缘的尘土堆积
	float dust = smoothstep(road_half_width * 0.60, road_half_width, edge);
	dust *= 0.4 + 0.6 * vnoise(vec2(along * 0.18, 9.1));
	col = mix(col, dirt_color.rgb * 1.12, dust * 0.5 * (1.0 - plaza_mode));

	// 潮湿斑块：更暗 + 更强高光
	float wet = smoothstep(0.42, 0.56, fbm2(wp * 0.13 + vec2(7.0, 2.0)));
	col *= 1.0 - 0.18 * wet;

	// 路肩 → 泥土过渡
	float shoulder = smoothstep(road_half_width, total_half_width, edge);
	col = mix(col, dirt_color.rgb, shoulder * (1.0 - plaza_mode));

	// 标线：仅中央白色虚线（线长 4m / 间隔 6m），路缘不画线
	float asp_mask = 1.0 - smoothstep(road_half_width - 0.06, road_half_width, edge);

	float phase = mod(along, 10.0);
	float dash = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(3.88, 4.0, phase));
	float center_lines = (1.0 - smoothstep(0.070, 0.100, abs(lateral))) * dash * asp_mask * (1.0 - plaza_mode);

	col = mix(col, center_line_color.rgb, center_lines);
	col = mix(col, col * (0.84 + 0.32 * grain), center_lines * 0.3);

	ALBEDO = col;

	float rough = roughness_base;
	rough += (grain - 0.5) * 0.16;
	rough -= 0.20 * wet;
	rough = mix(rough, 0.96, shoulder);
	ROUGHNESS = clamp(rough, 0.06, 1.0);

	// 湿斑区域提高 metallic，模拟积水反光
	METALLIC = wet * 0.12;

	// 微观凹凸：砂石颗粒的法线扰动，让沥青在光照下有实体颗粒感
	vec2 dp = wp * 11.0;
	float d0 = fbm2(dp);
	float dxn = fbm2(dp + vec2(0.35, 0.0));
	float dzn = fbm2(dp + vec2(0.0, 0.35));
	vec3 micro = vec3((d0 - dxn) * 16.0, 1.0, (d0 - dzn) * 16.0);
	NORMAL = normalize(mix(NORMAL, normalize(micro), 0.45));

	// 湿斑 rim：高光边缘光晕，模拟积水边缘漫反射
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = pow(rim, 3.0) * wet * 0.25;
	EMISSION = vec3(0.06, 0.07, 0.08) * rim;

	// 环境光遮蔽增强：基于粗糙度模拟接触阴影
	AO = mix(1.0, 0.6 + 0.4 * rough, 0.35);
	AO_LIGHT_AFFECT = 0.4;
}
