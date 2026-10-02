shader_type spatial;
render_mode cull_disabled;
// 草皮用交叉双片，必须双面可见。顺带也让缠绕方向变得无关紧要。
//
// 不用 depth_prepass_alpha：Mobile renderer（Android 目标）根本不跑深度预通道，
// Compatibility 在 4.3 之前也是空操作。
// 不用 alpha_to_coverage：Compatibility 从未实现（#98173），Web 上会被静默忽略。
//
// **ALPHA 必须写，而且必须和 ALPHA_SCISSOR_THRESHOLD 一起写。**
// scissor 判的就是 ALPHA，而 ALPHA 的默认值是 1.0 —— 只设
// ALPHA_SCISSOR_THRESHOLD 的话什么都不剔，整张卡片全不透明，
// 远看是一地绿色多边形而不是草。这个坑是截图看出来的：
// 头less 下 dummy renderer 不编译着色器，回归照样全绿。
// 写了 ALPHA 也不会掉进排序透明管线：引擎在
// ALPHA_SCISSOR_THRESHOLD 也被赋值时按不透明材质处理，
// 深度写入、正确排序、白送的阴影投射都还在。

// 实例化草皮卡片着色器（无贴图，适合 WebGL 导出）
// 一张卡片 = 一丛草，不是一根草：fragment 里用 blade_count 根解析式草叶
// 分割卡片 UV，这样"看着密"和"实例数少"就不矛盾了。
// 每根草叶的横向位置/倾斜/宽度/高度由 per-instance 的 INSTANCE_CUSTOM 决定。
// 卡片底色取自脚下那块地的世界坐标噪声，和地形 shader 是同一套 fbm 同一尺度，
// 所以草和地看不出接缝。

// 颜色整体退饱和过一轮。原来 blade_tip 是 (0.40,0.55,0.24)——绿通道比红通道
// 高 0.15、蓝通道几乎贴着红通道，是那种"塑料草坪"的纯度。真实草皮的黄化成分
// 很重：三个通道要往中间收，收完远景才接得上地形 shader（那边更灰）。
uniform vec4 blade_base     : source_color = vec4(0.290, 0.335, 0.225, 1.0);
uniform vec4 blade_tip      : source_color = vec4(0.470, 0.505, 0.360, 1.0);
uniform vec4 ground_color   : source_color = vec4(0.375, 0.475, 0.285, 1.0);
uniform vec4 ground_dark    : source_color = vec4(0.255, 0.335, 0.205, 1.0);

uniform float mottle_scale  : hint_range(0.01, 4.0) = 0.35;   // 必须与地形同尺度
// 卡片从 0.34×0.15 收到 0.24×0.085。定妆照拍出来的是一地龙舌兰：叶宽到
// 0.34m、只有 7 片，一丛草占掉半米见方，站近了就是一堵墙——而玩家相机离地
// 1.6m，这堵墙正好挡住前方的路。真实的路肩草是"矮而密"，靠的是**丛数**
// 而不是每丛的尺寸，所以下面 blade_count 反而要加。
uniform float card_width    : hint_range(0.05, 2.00) = 0.24;
uniform float card_height   : hint_range(0.05, 2.00) = 0.085;
// 7 → 10。卡片小了一半，丛数不变的话覆盖度会掉一半，所以每丛要多摊几片叶
// 才补得回来。循环上限同步放到 12（原来硬编码 8，改 blade_count 超过 8
// 会被静默截断——uniform 的 hint_range 上限也是 8，两处必须一起改）。
uniform float blade_count   : hint_range(1.0, 12.0) = 10.0;
uniform float alpha_cutoff  : hint_range(0.05, 0.95) = 0.32;
uniform float fade_start    : hint_range(1.0, 200.0) = 20.0;
uniform float fade_end      : hint_range(1.0, 200.0) = 30.0;
uniform float wind_amp      : hint_range(0.0, 0.5) = 0.055;
uniform float wind_freq     : hint_range(0.0, 8.0) = 1.7;
uniform float hue_jitter    : hint_range(0.0, 0.5) = 0.06;
uniform float blade_width   : hint_range(0.002, 0.100) = 0.011;  // 卡片 UV 里的半宽
uniform float width_floor   : hint_range(0.0, 3.0) = 0.70;      // 见 fragment 的注释

varying vec3 v_world;
varying vec3 v_ground;
varying vec3 v_card_n;
varying float v_vh;
varying float v_fade;
varying float v_seed_r;
varying float v_seed_h;

// 与 asphalt.gdshader / terrain_grass.gdshader 逐字一致的噪声工具
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

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	v += a * vnoise(p);
	v += a * vnoise(p * 2.02);
	return v;
}

void vertex() {
	// INSTANCE_CUSTOM 在 Compatibility 下是 16-bit 半精度，所以 CPU 侧只放 [0,1]
	// 的浮点，绝不能塞整数种子或位打包的 RNG 状态。
	vec4 seed = INSTANCE_CUSTOM;
	v_seed_r = seed.r;   // 主种子，fragment 用它派生每根草叶的形态
	v_vh = UV.y;         // 0 = 根部, 1 = 梢部。varying 必须在这里赋值，
	                      // 不能反过来在 vertex() 里读它（读到的是未定义值）
	v_seed_h = seed.b;   // hue 抖动

	float h = card_height * mix(0.75, 1.25, seed.g);

	// 淡出带：fade_end 之外高度塌成 0，让"预建环"只花顶点成本
	vec3 origin_w = MODEL_MATRIX[3].xyz;
	float dist = distance(origin_w, CAMERA_POSITION_WORLD);
	v_fade = clamp((fade_end - dist) / max(fade_end - fade_start, 0.001), 0.0, 1.0);

	// 风：单一全局方向 + 逐实例相位。草应该读成风，不是各摇各的噪点。
	// 位移随高度平方增长，所以根部不动、梢部摆幅最大。
	float phase = TIME * wind_freq + seed.a * 6.2831853
		+ origin_w.x * 0.35 + origin_w.z * 0.35;
	vec2 wind_dir = vec2(0.82, 0.57);
	float bend = wind_amp * v_vh * v_vh * (0.6 + 0.4 * sin(phase));

	vec3 p = VERTEX;
	// 卡片 mesh 建的是「单位宽」（底边半宽 0.5），实际 footprint 由
	// card_width 在这里缩放。否则宽度只能写死在 GDScript 建 mesh 时，
	// 调参就得重建 mesh。
	p.xz *= card_width;
	p.xz += wind_dir * bend * h;
	p.y *= h * v_fade;
	p.xz *= mix(0.6, 1.0, v_fade);

	v_world = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	// 底色在顶点阶段算（12 个顶点，不是几十个片元），噪声是世界坐标的纯函数，
	// 所以每丛草的根色正好等于它脚下那块地的颜色。
	v_ground = mix(ground_color.rgb, ground_dark.rgb,
		smoothstep(0.40, 0.95, fbm2(v_world.xz * mottle_scale)) * 0.75);
	// NORMAL 才是内置名（vertex 阶段可读）；写小写的 normal 会编译失败，
	// 而 --headless 用的是 dummy renderer，编译失败只报一行不中断运行。
	v_card_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 逐片元画 blade_count 根草叶，取覆盖度最高的那根
	float best = 0.0;
	float best_tip = 0.0;
	float n = max(1.0, blade_count);
	for (int i = 0; i < 12; i++) {
		if (float(i) >= n) {
			break;
		}
		float fi = float(i);
		vec2 hsh = vec2(
			hash12(vec2(v_seed_r * 311.7 + fi * 17.0, fi * 5.0 + 1.0)),
			hash12(vec2(v_seed_r * 197.3 + fi * 3.0, fi * 11.0 + 7.0)));

		float cx = mix(0.10, 0.90, hsh.x);
		float lean = (hsh.y - 0.5) * 0.50;                 // 越往上偏得越多
		float u = UV.x - cx - lean * v_vh * v_vh;
		// fwidth 做抗锯齿，分辨率无关；比固定宽度稳得多
		float aa = fwidth(u) * 1.2 + 1e-4;

		// 宽度必须有一道**屏幕空间下限**。真草叶只有 3~8mm 宽，远处
		// 一个像素都盖不满，光靠真实宽度会被 alpha scissor 一个不剩地剔掉，
		// 草皮直接消失。抬到 ~0.7 像素宽就还能看见，远景因此糊成
		// 一层草色的绒——这正是真实草在那个距离该有的样子，也是
		// GrassScatter 把 70m 外的卡片放大到 1.8~3.2 倍的依据。
		float halfw = max(blade_width * mix(0.7, 1.4, hsh.x), aa * width_floor)
			* (1.0 - 0.75 * v_vh);
		float m = 1.0 - smoothstep(halfw - aa, halfw + aa, abs(u));
		// 叶尖收窄。0.78 才是草——只在最梢部一小段收。收到 0.55 会让
		// 草叶读起来是龙舌兰那种又宽又尖的大叶子。
		m *= 1.0 - smoothstep(0.78, 1.0, v_vh + (hsh.y - 0.5) * 0.30);
		// 逐叶高度抖动，短叶不被长叶盖住
		m *= step(v_vh, mix(0.45, 1.0, hsh.y));

		if (m > best) {
			best = m;
			best_tip = smoothstep(0.0, 0.30, v_vh);
		}
	}

	best *= v_fade;
	ALPHA = best;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	vec3 blade = mix(blade_base.rgb, blade_tip.rgb, best_tip);
	// 根部吃 v_ground，往上逐渐长成草色，避免草和地之间出现硬边
	vec3 col = mix(v_ground, blade, smoothstep(0.0, 0.22, v_vh));
	col *= 1.0 + (v_seed_h - 0.5) * 2.0 * hue_jitter;

	ALBEDO = col;
	ROUGHNESS = 0.92;

	// cull_disabled 下没有背面剔除，法线要自己翻向相机。
	// 用 if 而不是 sign()：法线正对相机时 sign() 返回 0，normalize(0) 会出 NaN。
	NORMAL = normalize(dot(v_card_n, VIEW) < 0.0 ? -v_card_n : v_card_n);

	// 根部压暗，让草丛底部沉进地里而不是浮在地面上
	AO = mix(0.55, 1.0, smoothstep(0.0, 0.35, v_vh));
	AO_LIGHT_AFFECT = 0.6;
}
