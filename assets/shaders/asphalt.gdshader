shader_type spatial;
// Godot 4.6 cull_back 默认：cross.y<0 为正面。RoadBuilder 逐三角形
// 强制 cross.y<0，所以默认 cull_back 即可，无需 cull_disabled。

// 沥青路面程序化着色器（无贴图，适合 WebGL 导出）
// UV.x: 横向 0..1（覆盖路面+路肩全宽）  UV.y: 沿路距离 / tile_size
// v_world = (横向米数, 沿路米数)，噪声全部按世界尺度采样

// 反照率是这一族量到的量，不是调出来的观感。这两个常量带 `source_color`，
// 所以它们是 **sRGB**；而沥青的线性反照率大致 0.10~0.15，折回 sRGB 是 0.35~0.42。
// 旧值 0.168 折成线性只有 0.023——**比真实沥青暗四到五倍**，于是黄昏把太阳压到 9°
// 时路面直接黑掉（这一层是第四轮修好的）。
//
// **第四轮把亮度修好了，色相没修**，而这一轮修的是色相。原来这两个数是
// (0.355, 0.350, 0.340)——通道差只有 **0.015**，也就是一块**纯中性灰**。
// 真实沥青不是中性灰，它是**偏暖的深灰**；而这个世界的天穹是蓝的
// （`DAY_SKY_TOP` 的 b 是 r 的 3.5 倍），于是这块全场唯一大面积、近水平、
// 朝天的中性面把整片蓝天原样接了过来——**正午中位 `b−r` = +29、饱和度 0.252，
// 2× 放大读成靛蓝迷彩布**（第五轮 P0-1）。
//
// 三个成因假设逐个做过对照实验（`tools/probe_road_hue.gd`，一个进程只动一个旋钮）：
// · `EMISSION = 0`　　→ 路面 b−r 不变。**证伪**（自发光不是蓝的来源）
// · `ambient_light_energy = 0` → 路面 b−r **完全不变**。**证伪**
//   （`ambient_light_source = 3` 下这一路对漫反射几乎不参与，
//    所以整改计划里「收 `DAY_SKY_TOP` 的蓝」那条**改不到路面**：
//    实测把四个天空滤镜全拉黑，路面读数 +29 / 0.256，一格没动）
// · `SPECULAR = 0.0`　→ 只掉 3 个单位。证伪
// · **`sdfgi_enabled = false`** → +29 掉到 **+21**、饱和度 0.252 → 0.210。
//   **真凶是 SDFGI**：它是**从天空反推出来的间接反弹光**，既不乘
//   `DirectionalLight3D.light_color`、也不是 `ambient_light_energy` 那一路，
//   所以"把太阳换成纯红它还是蓝""把天拉黑它一点不变""三盏灯全灭它还亮着"
//   三件事同时成立。已在 `World3D.tscn` 里关掉。
//
// 而**材质这一侧仍然要改**：SDFGI 关掉之后 b−r 是 +21，而评审的门槛是 ±12。
// 抵消一份蓝辐照度只有一条路，就是给材质一份**暖**的偏色——真实沥青本来就该有。
// 现在通道差 0.100（r 0.430 / g 0.400 / b 0.330），实测正午
// `b−r = −3`、饱和度 0.092，两条都过了。`grain_dark_color` 按同一比例跟着走，
// 因为它按 `grain * 0.45` 混进来，留着中性只会把暖意稀释掉四成。
//
// **可推广的一条**：两盏灯都关掉之后路面仍然是 sRGB(6,17,70) 的**亮蓝**
// ——那一刻才想起来还有一个从没被拆过的光源。`grep` 场景文件只找得到手存的
// 那两盏灯，而这一盏是环境里的一个布尔量。
uniform vec4 asphalt_color     : source_color = vec4(0.430, 0.400, 0.330, 1.0);
uniform vec4 grain_dark_color  : source_color = vec4(0.258, 0.240, 0.198, 1.0);
// 路肩与路缘起灰那一层。**原来写着 vec4(0.300, 0.256, 0.184)——那是土**，
// 而它在路面上占的是 4.0~6.5m 那一条，加上往里 2.4m 的起灰渐变，
// 于是整条环路两侧读成两条泥带。现在换成**低饱和的灰砾石**
// （通道差 0.032）：铺法上和「沥青 → 碎石路肩」是一回事，
// 亮度还比沥青高一截（相对亮度 0.145 对 0.107），所以路肩是从路面上"退下去"的一层，
// 不是从路面上"长出来"的一层。回归 verify_asphalt_shader.gd 有一条
// 「`dirt_color` 的通道差 ≤ 0.06」钉着这件事——不然下一次调观感很容易调回土色。
uniform vec4 dirt_color        : source_color = vec4(0.430, 0.420, 0.398, 1.0);
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
	col = mix(col, grain_dark_color.rgb, grain * 0.45);
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

	// 路缘起灰：靠近路缘的细料堆积（不是尘土——`dirt_color` 已经是灰砾石了）
	float dust = smoothstep(road_half_width * 0.60, road_half_width, edge);
	dust *= 0.4 + 0.6 * vnoise(vec2(along * 0.18, 9.1));
	col = mix(col, dirt_color.rgb * 1.12, dust * 0.5 * (1.0 - plaza_mode));

	// 潮湿斑块：更暗 + 更强高光
	float wet = smoothstep(0.42, 0.56, fbm2(wp * 0.13 + vec2(7.0, 2.0)));
	col *= 1.0 - 0.18 * wet;

	// 路肩 → 碎石过渡（铺到 `total_half_width` 6.5m，正好接住 RoadVerge 的内沿）
	float shoulder = smoothstep(road_half_width, total_half_width, edge);
	col = mix(col, dirt_color.rgb, shoulder * (1.0 - plaza_mode));

	// 标线：中央白色虚线（线长 4m / 间隔 6m）+ 两侧沥青边上的白色实线。
	//
	// 边线这一条原来是**没有**的，而 `edge_line_color` 这个 uniform 一直挂在
	// 第 12 行没人读——一份声明了却从没被用过的 uniform，正是「写进字段不等于
	// 读进世界」那一族里最不容易被发现的一种：它在着色器里合法、没有任何报错。
	// 它同时治两样玩家读得出来的东西：
	//   ①沥青到路肩是**几何上的一刀切**（mesh 的外沿，|lateral| = road_half_width），
	//     切面上没有任何过渡，掠射角下读成一条锯齿。一条**在切面内侧**慢慢
	//     淡出的实线把人的视线钉在路缘上，锯齿于是有了去处。
	//   ②没有边线时，沥青到路肩是靠 `shoulder` 那条 smoothstep 混出来的，
	//     两色直接相接读成"路面画到一半断了"。（当年那一段还叠着"dirt 偏黄"
	//     这一条，而 dirt 现在已经是灰砾石了——这一条边线留着是因为它治的是
	//     **边界本身**，不是那两种颜色的色相差。）
	// 宽度 0.12m 的半宽是给抗锯齿留的余量：白线两侧各有 0.10m 的羽化，
	// 所以它在 1m 外的一辆自行车上仍是一条线，而它在 40m 外是一条会抖的亮带。
	float asp_mask = 1.0 - smoothstep(road_half_width - 0.06, road_half_width, edge);

	float phase = mod(along, 10.0);
	float dash = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(3.88, 4.0, phase));
	float center_lines = (1.0 - smoothstep(0.070, 0.100, abs(lateral))) * dash * asp_mask * (1.0 - plaza_mode);

	col = mix(col, center_line_color.rgb, center_lines);
	col = mix(col, col * (0.84 + 0.32 * grain), center_lines * 0.3);

	// 边线：贴着沥青外沿（road_half_width）**内侧**的一条实线，不随 dash 断续。
	// 中心线之所以要断续是因为它在路中间，而路缘线的作用是**定住那条边界**，
	// 断续的话边界反而读不出来了。中心距 0.12m → 半宽 0.12m 即 0.24m 宽。
	float d_edge = abs(abs(lateral) - (road_half_width - 0.18));
	float edge_line = (1.0 - smoothstep(0.06, 0.12, d_edge)) * (1.0 - plaza_mode);
	col = mix(col, edge_line_color.rgb, edge_line);
	col = mix(col, col * (0.84 + 0.32 * grain), edge_line * 0.3);

	ALBEDO = col;

	float rough = roughness_base;
	rough += (grain - 0.5) * 0.16;
	rough -= 0.20 * wet;
	rough = mix(rough, 0.96, shoulder);
	ROUGHNESS = clamp(rough, 0.06, 1.0);

	// 湿斑区域提高 metallic，模拟积水反光
	// 0.12 那版是"假高光"的代价：沥青不是金属，而 0.12 的金属度在湿斑上
	// 等于把它变成一面朝天的镜子，它映的是天空。降到 0.03 只留一点湿意。
	METALLIC = wet * 0.03;

	// 微观凹凸：砂石颗粒的法线扰动，让沥青在光照下有实体颗粒感
	// 三个数是一组的，改一个要连着两个改。玩家眼高 1.6m、看 1~3m 处的路面时
	// 一个像素盖住好几个特征，所以**特征必须大过一个像素**：旧版 11 周/米
	// ≈ 9cm 一个特征、梯度乘 16.0，于是每个微面片都在陡峭翻转——每个像素
	// 要么翻到天上（接到蓝天→蓝）、要么翻到地里（黑），那片蓝紫胡椒盐是
	// **走样**，不是斑块。现在特征放大到 17cm、梯度降到 4.0、混合降到 0.22。
	vec2 dp = wp * 6.0;
	float d0 = fbm2(dp);
	float dxn = fbm2(dp + vec2(0.35, 0.0));
	float dzn = fbm2(dp + vec2(0.0, 0.35));
	vec3 micro = vec3((d0 - dxn) * 4.0, 1.0, (d0 - dzn) * 4.0);
	NORMAL = normalize(mix(NORMAL, normalize(micro), 0.22));

	// 湿斑 rim：高光边缘光晕，模拟积水边缘漫反射
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = pow(rim, 3.0) * wet * 0.25;
	EMISSION = vec3(0.06, 0.07, 0.08) * rim;

	// 环境光遮蔽增强：基于粗糙度模拟接触阴影
	AO = mix(1.0, 0.6 + 0.4 * rough, 0.35);
	AO_LIGHT_AFFECT = 0.4;
}
