class_name LayoutData
## 布局覆盖数据 res://layout.json 的读写。
##
## 启动时由 World3D._setup_stations 读取 stations 覆盖驿站位置；
## 由 VegBuilder.setup() 的 plant_overrides 参数消费 plants 覆盖植被。
##
## Schema:
##   {
##     "version": 1,
##     "stations": [{"idx": 0, "pos": [x, y, z], "rot_y_deg": 0.0}, ...],
##     "plants":   [{"type": "bush", "pos": [x, y, z], "rot_y_deg": 0.0,
##                   "scale": 1.0, "seg_idx": 142}, ...]
##   }
## 容错:解析失败、字段缺失或类型不符时返回空字典,调用方跳过覆盖即可。

const PATH := "res://layout.json"
const SCHEMA_VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


## 返回 {stations: Array, plants: Array};任何阶段失败都返回 {}
static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("LayoutData: 无法打开 %s (err=%s)" % [PATH, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("LayoutData: %s 顶层不是 object" % PATH)
		return {}
	return parsed


## stations: Array of {idx:int, pos:Vector3, rot_y_deg:float}
## plants:   Array of {type:String, pos:Vector3, rot_y_deg:float, scale:float, seg_idx:int}
static func save(stations: Array, plants: Array) -> int:
	var data := {
		"version": SCHEMA_VERSION,
		"stations": _serialize_stations(stations),
		"plants": _serialize_plants(plants),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("LayoutData: 无法写入 %s (err=%s)" % [PATH, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return OK


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## 把编辑器内 stations 状态序列化为 JSON 友好的纯数组/dict
static func _serialize_stations(stations: Array) -> Array:
	var out := []
	for s in stations:
		var pos: Vector3 = s.get("pos", Vector3.ZERO)
		out.append({
			"idx": int(s.get("idx", -1)),
			"pos": [pos.x, pos.y, pos.z],
			"rot_y_deg": float(s.get("rot_y_deg", 0.0)),
		})
	return out


static func _serialize_plants(plants: Array) -> Array:
	var out := []
	for p in plants:
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		out.append({
			"type": String(p.get("type", "")),
			"pos": [pos.x, pos.y, pos.z],
			"rot_y_deg": float(p.get("rot_y_deg", 0.0)),
			"scale": float(p.get("scale", 1.0)),
			"seg_idx": int(p.get("seg_idx", 0)),
		})
	return out


## 给 World3D 用:从 load() 返回的字典里挑出 stations[idx] 的覆盖项
## 返回 {pos: Vector3, rot_y_deg: float} 或 {} 表示无覆盖
static func get_station_override(data: Dictionary, idx: int) -> Dictionary:
	if not data.has("stations"):
		return {}
	for s in data["stations"]:
		if not (s is Dictionary):
			continue
		if int(s.get("idx", -1)) != idx:
			continue
		var pos_arr = s.get("pos", [])
		var result := {}
		if pos_arr is Array and pos_arr.size() >= 3:
			result["pos"] = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		result["rot_y_deg"] = float(s.get("rot_y_deg", 0.0))
		return result
	return {}


## 给 VegBuilder 用:按 type 分组返回 {type: Array of {pos, rot_y_deg, scale, seg_idx}}
## 缺字段或类型不符的项跳过
static func get_plant_overrides_by_type(data: Dictionary) -> Dictionary:
	var out := {}
	if not data.has("plants"):
		return out
	for p in data["plants"]:
		if not (p is Dictionary):
			continue
		var t: String = String(p.get("type", ""))
		if t.is_empty():
			continue
		var pos_arr = p.get("pos", [])
		if not (pos_arr is Array) or pos_arr.size() < 3:
			continue
		var entry := {
			"pos": Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
			"rot_y_deg": float(p.get("rot_y_deg", 0.0)),
			"scale": float(p.get("scale", 1.0)),
			"seg_idx": int(p.get("seg_idx", 0)),
		}
		if not out.has(t):
			out[t] = []
		out[t].append(entry)
	return out