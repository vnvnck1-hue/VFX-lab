## 노드 그래프 → canvas_item 셰이더 코드.
## 숫자/색 파라미터는 uniform 으로 빼서, 값만 바뀔 때는 다시 컴파일하지 않고 uniform 만 갱신한다.
@tool
class_name VfxForgeCompiler
extends RefCounted

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")
const LIB_PATH := "res://addons/vfx_forge/shaders/vfx_lib.gdshaderinc"

const UNIFORM_TYPES := {
	"float": "float", "int": "int", "enum": "int", "bool": "float",
	"color": "vec4", "vec2": "vec2", "gradient": "sampler2D",
}


static func uniform_name(node_id: int, param: String) -> String:
	return "n%d_%s" % [node_id, param]


static func out_var(node_id: int, out_name: String) -> String:
	return "n%d_o_%s" % [node_id, out_name]


## 타입 변환 식
static func convert_expr(expr: String, from: int, to: int) -> String:
	if from == to:
		return expr
	match [from, to]:
		[Lib.FLOAT, Lib.COLOR]:
			return "vec4(vec3(%s), 1.0)" % expr
		[Lib.FLOAT, Lib.UV]:
			return "vec2(%s)" % expr
		[Lib.COLOR, Lib.FLOAT]:
			return "vfx_lum(%s)" % expr
		[Lib.COLOR, Lib.UV]:
			return "(%s).rg" % expr
		[Lib.UV, Lib.FLOAT]:
			return "(%s).x" % expr
		[Lib.UV, Lib.COLOR]:
			return "vec4(%s, 0.0, 1.0)" % expr
	return expr


## root 에 필요한 노드들을 의존 순서대로 돌려준다
static func _topo_order(graph: VfxForgeGraph, root: int) -> Array:
	var order := []
	var state := {}  # 1 = 방문 중, 2 = 완료
	var stack := [[root, false]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var id: int = item[0]
		if item[1]:
			if state.get(id, 0) != 2:
				state[id] = 2
				order.append(id)
			continue
		if state.get(id, 0) != 0:
			continue
		state[id] = 1
		stack.append([id, true])
		for c in graph.connections:
			if c.to == id and graph.nodes.has(c.from) and state.get(c.from, 0) == 0:
				stack.append([c.from, false])
	return order


## 결과: {"ok", "error", "code", "uniforms": [{"name", "type", "node", "param"}]}
## target_id 를 주면 그 노드의 첫 출력을 그대로 보여주는 미리보기용 셰이더를 만든다.
static func compile(graph: VfxForgeGraph, target_id := -1) -> Dictionary:
	var root := target_id if target_id >= 0 and graph.nodes.has(target_id) else graph.output_node()
	if root < 0:
		return {"ok": false, "error": "출력(Output) 노드가 없습니다.", "code": "", "uniforms": []}

	var order := _topo_order(graph, root)
	var uniforms := []
	var decls := PackedStringArray()
	var body := PackedStringArray()

	for id in order:
		var node: Dictionary = graph.nodes[id]
		var def := Lib.get_def(node.type)
		var subs := {}

		# 일반 입력
		for inp in def.inputs:
			var c := graph.input_connection(id, inp.name)
			if not c.is_empty() and graph.nodes.has(c.from):
				subs[inp.name] = _connected_expr(graph, c, inp.type)
			elif inp.type == Lib.UV:
				subs[inp.name] = "uv"
			else:
				subs[inp.name] = inp.get("default", "0.0")

		# 파라미터 (포트로 연결된 건 연결 식, 아니면 uniform)
		for p in def.params:
			var c := graph.input_connection(id, p.name) if p.get("port", false) else {}
			if not c.is_empty() and graph.nodes.has(c.from):
				subs[p.name] = "(" + _connected_expr(graph, c, Lib.COLOR if p.type == "color" else Lib.FLOAT) + ")"
				continue
			var un := uniform_name(id, p.name)
			subs[p.name] = un
			if p.type == "bezier":
				decls.append("uniform vec2 %s_p[%d];" % [un, Lib.MAX_BEZIER_KEYS * 4])
				decls.append("uniform vec4 %s_d[%d];" % [un, Lib.MAX_BEZIER_KEYS])
				decls.append("uniform float %s_t[%d];" % [un, Lib.MAX_BEZIER_KEYS])
				decls.append("uniform int %s_n;" % un)
			elif p.type == "gradient":
				decls.append("uniform sampler2D %s : filter_linear, repeat_disable;" % un)
			else:
				decls.append("uniform %s %s;" % [UNIFORM_TYPES[p.type], un])
			uniforms.append({"name": un, "type": p.type, "node": id, "param": p.name})

		subs["t"] = "t"
		body.append("\t// %s (#%d)" % [def.title, id])
		if def.has("pre"):
			for line in _fill(def.pre, subs, id).split("\n"):
				body.append("\t" + line)
		for o in def.outputs:
			body.append("\t%s %s = %s;" % [Lib.GLSL_TYPES[o.type], out_var(id, o.name), _fill(o.expr, subs, id)])

	var root_def := Lib.get_def(graph.nodes[root].type)
	var first_out: Dictionary = root_def.outputs[0]
	var ret := convert_expr(out_var(root, first_out.name), first_out.type, Lib.COLOR)

	var code := PackedStringArray()
	code.append("// VFX Forge 가 자동 생성한 셰이더입니다. 직접 고치지 말고 레시피를 수정하세요.")
	code.append("shader_type canvas_item;")
	code.append("render_mode blend_disabled, unshaded;")
	code.append("#include \"%s\"" % LIB_PATH)
	code.append("")
	code.append_array(decls)
	code.append("")
	code.append("vec4 vfx_graph(vec2 uv, float t) {")
	code.append_array(body)
	code.append("\treturn %s;" % ret)
	code.append("}")
	code.append("")
	code.append(FRAGMENT)
	return {"ok": true, "error": "", "code": "\n".join(code), "uniforms": uniforms}


const FRAGMENT := """void fragment() {
	vec2 uv;
	float t;
	if (vfx_sheet == 1) {
		vec2 grid = vec2(float(vfx_cols), float(vfx_rows));
		vec2 cellf = UV * grid;
		vec2 cell = min(floor(cellf), grid - 1.0);
		uv = cellf - cell;
		int idx = int(cell.y) * vfx_cols + int(cell.x);
		int n = vfx_cols * vfx_rows;
		t = vfx_loop > 0.5 ? float(idx) / float(n) : float(idx) / float(max(n - 1, 1));
	} else {
		uv = fract(UV * vfx_preview_repeat);
		t = vfx_t;
	}
	COLOR = vfx_graph(uv, t);
}"""


static func _connected_expr(graph: VfxForgeGraph, c: Dictionary, to_type: int) -> String:
	var from_def := Lib.get_def(graph.nodes[c.from].type)
	var idx := Lib.output_index(from_def, c.from_port)
	if idx < 0:
		idx = 0
	var o: Dictionary = from_def.outputs[idx]
	return convert_expr(out_var(c.from, o.name), o.type, to_type)


## {이름} / {$지역변수} 치환. 기본값 식이 다른 입력을 참조할 수 있어서 두 번 돌린다.
static func _fill(tpl: String, subs: Dictionary, id: int) -> String:
	var s := tpl
	for _pass in 2:
		var re := RegEx.create_from_string("\\{(\\$?)([a-z_0-9]+)\\}")
		var out := ""
		var last := 0
		for m in re.search_all(s):
			out += s.substr(last, m.get_start() - last)
			var key := m.get_string(2)
			if m.get_string(1) == "$":
				out += "n%d_l_%s" % [id, key]
			elif subs.has(key):
				out += str(subs[key])
			else:
				out += m.get_string()
			last = m.get_end()
		out += s.substr(last)
		s = out
	return s
