## VFX Forge 레시피(노드 그래프) 데이터. JSON(.vfx.json)으로 저장/불러온다.
@tool
class_name VfxForgeGraph
extends RefCounted

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")
const FORMAT := "vfx_forge_recipe"
const VERSION := 1

const DEFAULT_SETTINGS := {
	"frame_size": 512,       # 프레임 한 칸 픽셀 (256 / 512 / 1024)
	"cols": 4,
	"rows": 4,
	"loop": true,            # 루프 애니메이션이면 마지막 프레임 다음이 첫 프레임
	"usage": "effect",       # effect = 단독 이펙트, strip = 가로로 이어지는 띠(트레일), tile = 상하좌우 반복
	"import_preset": "2d",   # 2d = 무손실/밉맵 없음, 3d = VRAM 압축 + 밉맵
	"export_path": "",
	"fps": 24.0,
	"make_sprite_frames": true,
	"make_particle_material": true,
	"blend": "add",          # 생성되는 머티리얼의 블렌드 (add / mix)
}

var name := "Untitled"
var settings := DEFAULT_SETTINGS.duplicate(true)
## id(int) -> {"id", "type", "pos": Vector2, "params": {name: value}}
var nodes := {}
## [{"from": id, "from_port": 출력 이름, "to": id, "to_port": 입력/파라미터 이름}]
var connections: Array = []
var next_id := 1


static func create_default() -> VfxForgeGraph:
	var g := VfxForgeGraph.new()
	var c := g.add_node("circle", Vector2(40, 40))
	g.nodes[c].params.outline = true
	g.nodes[c].params.thickness = 0.06
	g.nodes[c].params.softness = 0.02
	var col := g.add_node("colorize", Vector2(320, 60))
	g.nodes[col].params.color = Color(0.4, 0.85, 1.0)
	var out := g.add_node("output", Vector2(580, 60))
	g.connect_ports(c, "mask", col, "mask")
	g.connect_ports(col, "color", out, "color")
	return g


## 파라미터 기본값을 메모리용 Godot 타입으로 바꾼다
static func param_from_json(p: Dictionary, v):
	match p.type:
		"float":
			return float(v)
		"int", "enum":
			return int(v)
		"bool":
			return bool(v)
		"color":
			return Color.html(v) if v is String else Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
		"vec2":
			return Vector2(v[0], v[1])
		"gradient":
			var stops := []
			for s in v:
				stops.append([float(s[0]), Color.html(s[1]) if s[1] is String else Color(s[1][0], s[1][1], s[1][2], s[1][3])])
			stops.sort_custom(func(a, b): return a[0] < b[0])
			return stops
		"bezier":
			var keys := []
			for k in v:
				var pts: Array[Vector2] = []
				for q in k.p:
					pts.append(Vector2(q[0], q[1]))
				keys.append({"t": float(k.t), "p": pts, "head": float(k.get("head", 1.0)), "tail": float(k.get("tail", 0.0)), "width": float(k.get("width", 0.05))})
			keys.sort_custom(func(a, b): return a.t < b.t)
			return keys
	return v


static func param_to_json(p: Dictionary, v):
	match p.type:
		"color":
			return "#" + (v as Color).to_html(true)
		"vec2":
			return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]
		"float":
			return snappedf(v, 0.00001)
		"gradient":
			var out := []
			for s in v:
				out.append([snappedf(s[0], 0.0001), "#" + (s[1] as Color).to_html(true)])
			return out
		"bezier":
			var out := []
			for k in v:
				var pts := []
				for q in k.p:
					pts.append([snappedf(q.x, 0.0001), snappedf(q.y, 0.0001)])
				out.append({"t": snappedf(k.t, 0.0001), "p": pts, "head": snappedf(k.head, 0.0001), "tail": snappedf(k.tail, 0.0001), "width": snappedf(k.width, 0.0001)})
			return out
	return v


func add_node(type: String, pos: Vector2, id := -1) -> int:
	var def := Lib.get_def(type)
	if def.is_empty():
		push_error("VFX Forge: 알 수 없는 노드 타입 " + type)
		return -1
	if id < 0:
		id = next_id
	next_id = maxi(next_id, id + 1)
	var params := {}
	for p in def.params:
		params[p.name] = param_from_json(p, p.default)
	nodes[id] = {"id": id, "type": type, "pos": pos, "params": params}
	return id


func remove_node(id: int) -> void:
	nodes.erase(id)
	connections = connections.filter(func(c): return c.from != id and c.to != id)


func output_node() -> int:
	for id in nodes:
		if nodes[id].type == "output":
			return id
	return -1


func input_connection(to: int, to_port: String) -> Dictionary:
	for c in connections:
		if c.to == to and c.to_port == to_port:
			return c
	return {}


func is_connected_input(to: int, to_port: String) -> bool:
	return not input_connection(to, to_port).is_empty()


## from 이 to 의 조상이면(= to 에서 거슬러 올라가 from 에 닿으면) 연결 시 순환이 생긴다
func _reaches(start: int, target: int) -> bool:
	if start == target:
		return true
	var stack := [start]
	var seen := {}
	while not stack.is_empty():
		var n: int = stack.pop_back()
		if n == target:
			return true
		if seen.has(n):
			continue
		seen[n] = true
		for c in connections:
			if c.to == n:
				stack.append(c.from)
	return false


func connect_ports(from: int, from_port: String, to: int, to_port: String) -> bool:
	if not nodes.has(from) or not nodes.has(to):
		return false
	# to 의 출력이 이미 from 으로 흘러가고 있으면 순환
	if _reaches(from, to):
		return false
	disconnect_input(to, to_port)
	connections.append({"from": from, "from_port": from_port, "to": to, "to_port": to_port})
	return true


func disconnect_input(to: int, to_port: String) -> void:
	connections = connections.filter(func(c): return not (c.to == to and c.to_port == to_port))


func to_dict() -> Dictionary:
	var out_nodes := []
	var ids := nodes.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = nodes[id]
		var def := Lib.get_def(n.type)
		var params := {}
		for p in def.params:
			params[p.name] = param_to_json(p, n.params[p.name])
		out_nodes.append({"id": id, "type": n.type, "pos": [roundi(n.pos.x), roundi(n.pos.y)], "params": params})
	var conns := []
	for c in connections:
		conns.append({"from": c.from, "from_port": c.from_port, "to": c.to, "to_port": c.to_port})
	return {"format": FORMAT, "version": VERSION, "name": name, "settings": settings.duplicate(true), "nodes": out_nodes, "connections": conns}


static func from_dict(d: Dictionary) -> VfxForgeGraph:
	var g := VfxForgeGraph.new()
	g.name = d.get("name", "Untitled")
	var s: Dictionary = d.get("settings", {})
	for k in s:
		if g.settings.has(k):
			var def_v = g.settings[k]
			g.settings[k] = type_convert(s[k], typeof(def_v))
	for nd in d.get("nodes", []):
		var id := g.add_node(nd.type, Vector2(nd.pos[0], nd.pos[1]), int(nd.id))
		if id < 0:
			continue
		var def := Lib.get_def(nd.type)
		var params: Dictionary = nd.get("params", {})
		for p in def.params:
			if params.has(p.name):
				g.nodes[id].params[p.name] = param_from_json(p, params[p.name])
	for c in d.get("connections", []):
		g.connections.append({"from": int(c.from), "from_port": str(c.from_port), "to": int(c.to), "to_port": str(c.to_port)})
	return g


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", false)


func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	return OK


static func load_file(path: String) -> VfxForgeGraph:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or data.get("format", "") != FORMAT:
		return null
	return from_dict(data)


func duplicate_graph() -> VfxForgeGraph:
	return from_dict(JSON.parse_string(to_json()))


## 시트 프레임 수와 i 번째 프레임의 시간 (셰이더와 같은 규칙)
func frame_count() -> int:
	return int(settings.cols) * int(settings.rows)


func frame_time(i: int) -> float:
	var n := frame_count()
	if settings.loop:
		return float(i) / float(n)
	return float(i) / float(maxi(n - 1, 1))


func tiling() -> Vector2:
	match settings.usage:
		"strip":
			return Vector2(1, 0)
		"tile":
			return Vector2(1, 1)
	return Vector2.ZERO
