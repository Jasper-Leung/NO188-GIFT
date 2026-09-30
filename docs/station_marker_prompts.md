# 驿站建筑 3D 模型提示词设计

## 设计原则

1. **风格统一**：中式山地建筑，自然质朴
2. **体量适中**：每座建筑约 4-6 米宽，3-5 米高，适合游戏引擎
3. **结构差异**：通过建筑形态体现各驿站功能与地形
4. **低面数友好**：适合 Godot WebGL 导出

---

## 建筑类型分类

| 类型 | 驿站 | 描述 |
|------|------|------|
| 门廊式 | 起点路标、东浦路标、南谷路标、右岭路标 | 三开间木构门廊，青瓦顶，立柱有雕刻 |
| 弯道亭 | 右弯路标、左弯路标 | 半开放弯道亭，带方向指示 |
| 水榭式 | 西湾路标 | 临水建筑，水波纹装饰 |
| 交叉廊 | 交叉点路标 | 双向廊道，双面牌匾 |
| 山居式 | 北口路标、西谷路标 | 山地民居风格，厚重沉稳 |

---

## 各驿站四视图提示词

### 0. 起点路标 (Trailhead Pavilion)

**建筑形态**：三开间木构门楼，双重檐顶，正脊有"始"字雕饰，中央开门洞，两侧立柱，基础石台

```
中式三开间木构门楼建筑，双重悬山顶，青瓦覆盖，
正脊中央"始"字雕饰，中央开矩形门洞，
两侧四根立柱立于石质台基，柱间横梁连接，
木构部分赭红色油漆，斑驳风化，
三间宽度约5米，建筑高约4米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese three-bay wooden gatehouse pavilion, double swooping roof with dark grey tiles,
central rectangular doorway, four wooden pillars on stone plinth,
roof ridge with "始" character ornament,
wood grain texture, vermilion paint, weathered patina,
game engine ready, low-poly style, realistic scale approximately 5m wide 4m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 1. 东浦路标 (East Cove Pavilion)

**建筑形态**：单开间临水廊舍，鱼形瓦当装饰，青瓦顶，木质台基临水外挑

```
中式单开间临水廊舍建筑，悬山顶覆青瓦，
檐口鱼形瓦当装饰，两根立柱立于水中石砌基础，
侧面木栏杆，廊内设木质坐凳，
木纹材质，青灰瓦，水面倒影效果，
建筑宽约4米，进深约3米，高约3.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese single-bay waterfront pavilion, single sloping roof with blue-grey tiles,
fish-shaped tile ornament at eaves, two wooden pillars on stone foundation extending over water,
side wooden railing, wooden bench inside, wood grain texture,
blue-grey roof tiles, water reflection atmosphere,
game engine ready, low-poly style, approximately 4m wide 3.5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 2. 南谷路标 (South Valley Pavilion)

**建筑形态**：茅草顶山地农舍，稻草色覆盖，木墙，稻穗装饰挂件，质朴田园风格

```
中式山地茅草农舍，稻草铺大屋顶，悬山式木构，
木墙框架，门前木廊柱两根，
横梁挂稻穗装饰篓筐，木质门窗，
茅草金黄色，木墙原木色，田园质朴风格，
建筑宽约5米，深约4米，高约3.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese mountain farmhouse with thatched roof, thatched straw covering,
timber frame walls, two front pillars forming a porch,
rice ear decorative baskets hanging from beams, wooden doors and windows,
thatched golden yellow, log-colored walls, rustic countryside style,
game engine ready, low-poly style, approximately 5m wide 3.5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 3. 右岭路标 (Right Ridge Pavilion)

**建筑形态**：石砌基础木构山亭，重檐灰瓦，山形浮雕立柱，山地粗犷风格

```
中式山地石砌凉亭，重檐四柱，灰瓦覆盖，
石砌台基约半米高，四根粗木柱立于石上，
柱间有山形浅浮雕装饰，
木柱赭石色，石基青灰色，瓦深灰，
建筑约5米见方，高约4.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese mountain stone pavilion, double-eaved roof with dark grey tiles,
stone plinth 0.5m high, four thick wooden pillars on stone base,
mountain shape bas-relief decoration on pillars,
ochre wooden pillars, blue-grey stone base, dark grey tiles,
game engine ready, low-poly style, approximately 5m square 4.5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 5. 右弯路标 (Right Bend Pavilion)

**建筑形态**：半圆形开放弯道亭，弧形屋面指向右转，箭头地砖装饰

```
中式半圆形弯道开放亭，弧形青瓦屋面呈右转指向，
六根木柱支撑，柱间无墙仅栏杆，
弧形石质地砖铺地，带右转弯箭头图案，
屋檐下弧形牌匾刻"右弯"，
木柱深褐色，青灰瓦，半开放通透，
直径约5米，高约3.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese semicircular bend pavilion, curved roof pointing right,
six wooden pillars with railing between, open sides,
curved stone floor tiles with right-turn arrow pattern,
curved plaque beneath eaves showing "右弯",
dark brown wooden pillars, blue-grey tiles, semi-open design,
game engine ready, low-poly style, approximately 5m diameter 3.5m tall,
front view, side view|top view|perspective view,
realistic rendering, transparent background
```

---

### 6. 西湾路标 (West Cove Pavilion)

**建筑形态**：水榭式临水建筑，水波纹挂落装饰，青瓦卷棚，平台挑出水面

```
中式水榭式临水建筑，卷棚悬山顶覆青瓦，
檐口水波纹木雕挂落，两根立柱支承，
平台石砌伸出水面，台边石栏杆，
水面荷叶浮雕石板铺地，
木构青灰瓦，水面倒影意境，
建筑宽约6米，平台挑出1.5米，高约4米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese waterside pavilion, curved ceiling with blue-grey tiles,
water wave wooden lattice under eaves, two wooden pillars,
stone platform extending over water with stone railing,
lotus leaf carved stone slabs on floor,
wood structure, blue-grey tiles, water reflection atmosphere,
game engine ready, low-poly style, approximately 6m wide 4m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 8. 交叉点路标 (Crossing Pavilion)

**建筑形态**：十字形双向廊道，四向敞开，双面牌匾指示，双向出入口

```
中式十字形双向廊道建筑，四面敞开，青瓦攒尖顶，
中央四柱，四向各有牌匾，双面刻字指示，
石质地砖十字铺装，柱间底部石凳，
木柱深褐色，攒尖顶，青灰瓦，
建筑四向各约4米，中央高约5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese cross-shaped dual-direction corridor pavilion,
pointed roof with blue-grey tiles, open on all four sides,
four central pillars, dual-face plaques on each side,
stone brick cross-shaped floor, stone benches at pillar bases,
dark brown wooden pillars, pointed roof,
game engine ready, low-poly style, approximately 4m each direction 5m tall at center,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 9. 北口路标 (North Pass Pavilion)

**建筑形态**：厚重山地门楼，石砌墙裙，重檐青瓦，松枝装饰，凛然气势

```
中式厚重山地门楼，重檐青瓦顶，脊饰威严，
石砌勒脚墙裙，高约1米，五开间门廊，
六根粗大立柱，柱头松枝浮雕，
门楣挂"北口"牌匾，两侧石狮蹲坐，
木柱深褐色，石基青灰厚重，青瓦沉稳，
建筑宽约7米，高约5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese massive mountain gatehouse, double-eaved roof with blue-grey tiles,
stone wall plinth 1m high, five-bay porch,
six thick pillars with pine branch capitals,
"北口" plaque on lintel, stone lions sitting on sides,
dark brown wooden pillars, blue-grey stone base, dignified atmosphere,
game engine ready, low-poly style, approximately 7m wide 5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 11. 左弯路标 (Left Bend Pavilion)

**建筑形态**：半圆形开放弯道亭，弧形屋面指向左转，箭头地砖装饰

```
中式半圆形弯道开放亭，弧形青瓦屋面呈左转指向，
六根木柱支撑，柱间仅栏杆通透，
弧形石质地砖铺地，带左转弯箭头图案，
弧形牌匾刻"左弯"挂于檐下，
木柱深褐色，青灰瓦，半开放轻盈，
直径约5米，高约3.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese semicircular bend pavilion, curved roof pointing left,
six wooden pillars with railing between, open sides,
curved stone floor tiles with left-turn arrow pattern,
curved plaque beneath eaves showing "左弯",
dark brown wooden pillars, blue-grey tiles, semi-open lightweight design,
game engine ready, low-poly style, approximately 5m diameter 3.5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

### 12. 西谷路标 (West Valley Pavilion)

**建筑形态**：谷地民居风格石砌建筑，重檐青瓦，檐口谷形装饰，敦实厚重

```
中式谷地民居风格建筑，石砌墙基约1米高，
重檐悬山顶覆青瓦，檐口谷形瓦当装饰，
木构框架，木门木窗，门前两根廊柱，
木墙原木色，石基青灰，瓦深灰青，
整体敦实厚重，山谷隐居风格，
建筑宽约6米，深约5米，高约4.5米，
4K分辨率，正视图|侧视图|顶视图|透视图，
写实渲染，背景透明
```

**Tripo 3D 提示词**：
```
A traditional Chinese valley farmhouse style building, stone wall base 1m high,
double-eaved sloping roof with blue-grey tiles, valley-shaped tile ornaments at eaves,
timber frame, wooden doors and windows, two front pillars,
log-colored wooden walls, blue-grey stone, dark grey-blue tiles,
solid and grounded, valley retreat atmosphere,
game engine ready, low-poly style, approximately 6m wide 4.5m tall,
front view, side view, top view, perspective view,
realistic rendering, transparent background
```

---

## 输出文件命名规范

| 驿站 | 文件名 | 建筑类型 |
|------|--------|----------|
| 起点路标 | station_6.glb | 三开间门楼 |
| 东浦路标 | station_7.glb | 临水廊舍 |
| 南谷路标 | station_8.glb | 茅草农舍 |
| 右岭路标 | station_9.glb | 山地石亭 |
| 右弯路标 | station_10.glb | 弯道亭 |
| 西湾路标 | station_11.glb | 临水水榭 |
| 交叉点路标 | station_12.glb | 十字廊亭 |
| 北口路标 | station_13.glb | 山地门楼 |
| 左弯路标 | station_14.glb | 弯道亭 |
| 西谷路标 | station_15.glb | 谷地民居 |
