## VisualShader 그래프를 코드로 조립하기 위한 공용 헬퍼.
## 생성기 스크립트에서 `const VSBuilder := preload("res://tools/vs_builder.gd")` 로 불러 쓴다.
extends RefCounted

var vs := VisualShader.new()
var type := VisualShader.TYPE_FRAGMENT
var _next_id := 2  # 0 = Output 노드, 1 은 예약


func _init(mode: VisualShader.Mode) -> void:
	vs.set_mode(mode)


func add(node: VisualShaderNode, x: float, y: float) -> int:
	var id := _next_id
	_next_id += 1
	vs.add_node(type, node, Vector2(x, y), id)
	return id


## 노드 포트를 인덱스로 연결한다. to_id 가 0(Output 노드)이면 to_port 에 생성 코드의 대입 대상("EMISSION", "COLOR.rgb" 등)을 써도 된다.
func link(from_id: int, from_port: int, to_id: int, to_port) -> void:
	var tp: int = to_port if to_port is int else output_port(to_port)
	var err := vs.connect_nodes(type, from_id, from_port, to_id, tp)
	if err != OK:
		push_error("connect failed: %d:%d -> %d:%s (err %d)" % [from_id, from_port, to_id, to_port, err])


## Output 노드의 포트 순서는 엔진 버전마다 바뀌고 스크립트로 조회할 수 없어서,
## 임시 셰이더에 상수를 꽂아 생성 코드에 어떤 대입문(EMISSION = / COLOR.rgb = 등)이 나오는지로 역탐색한다.
func output_port(builtin: String) -> int:
	var target := "	" + builtin + " ="
	for i in 64:
		var probe := VisualShader.new()
		probe.set_mode(vs.get_mode())
		probe.add_node(type, VisualShaderNodeFloatConstant.new(), Vector2.ZERO, 2)
		if probe.connect_nodes(type, 2, 0, 0, i) != OK:
			continue
		if probe.get_code().contains(target):
			return i
	push_error("output port not found: " + builtin)
	return -1


func save(path: String) -> void:
	vs.set_node_position(type, 0, Vector2(600, 0))
	var err := ResourceSaver.save(vs, path)
	if err != OK:
		push_error("save failed: %s (err %d)" % [path, err])


# ================= 수식형 헬퍼 =================
# 피연산자(operand)는 노드 id(int, 출력 포트 0) / Vector2i(id, 포트) / float 리터럴(포트 기본값으로 박힘) 중 하나.

func wire(operand, to_id: int, to_port: int) -> void:
	match typeof(operand):
		TYPE_INT:
			link(operand, 0, to_id, to_port)
		TYPE_VECTOR2I:
			link(operand.x, operand.y, to_id, to_port)
		TYPE_FLOAT:
			vs.get_node(type, to_id).set_input_port_default_value(to_port, operand)
		_:
			push_error("bad operand: %s" % operand)


func node_with(node: VisualShaderNode, operands: Array, pos: Vector2) -> int:
	var id := add(node, pos.x, pos.y)
	for i in operands.size():
		wire(operands[i], id, i)
	return id


func fop(op: VisualShaderNodeFloatOp.Operator, a, b, pos: Vector2) -> int:
	return node_with(float_op(op), [a, b], pos)


func ffunc(f: VisualShaderNodeFloatFunc.Function, a, pos: Vector2) -> int:
	return node_with(float_func(f), [a], pos)


func sstep(e0, e1, x, pos: Vector2) -> int:
	return node_with(smoothstep_node(), [e0, e1, x], pos)


func mixf(a, b, t, pos: Vector2) -> int:
	return node_with(mix_node(VisualShaderNodeMix.OP_TYPE_SCALAR), [a, b, t], pos)


func mix3(a, b, t, pos: Vector2) -> int:
	return node_with(mix_node(VisualShaderNodeMix.OP_TYPE_VECTOR_3D_SCALAR), [a, b, t], pos)


func vec2(a, b, pos: Vector2) -> int:
	return node_with(compose(VisualShaderNodeVectorCompose.OP_TYPE_VECTOR_2D), [a, b], pos)


func len2(v, pos: Vector2) -> int:
	var n := VisualShaderNodeVectorLen.new()
	n.op_type = VisualShaderNodeVectorLen.OP_TYPE_VECTOR_2D
	return node_with(n, [v], pos)


## 텍스처를 fract(uv) 로 샘플해 Vector4 decompose 노드 id 를 돌려준다 (출력 0 = r).
## Texture 노드의 내장 sampler 는 반복(repeat) 힌트가 없어 2D 에선 clamp 되므로, 스크롤하는 UV 는 fract 로 감싼다.
func sample_r(tex_node: VisualShaderNodeTexture, uv, pos: Vector2) -> int:
	var fract := VisualShaderNodeVectorFunc.new()
	fract.op_type = VisualShaderNodeVectorFunc.OP_TYPE_VECTOR_2D
	fract.function = VisualShaderNodeVectorFunc.FUNC_FRACT
	var wrapped := node_with(fract, [uv], pos - Vector2(200, 0))
	var t := node_with(tex_node, [wrapped], pos)
	return node_with(decompose(VisualShaderNodeVectorDecompose.OP_TYPE_VECTOR_4D), [t], pos + Vector2(200, 0))


# ================= 노드 팩토리 =================

func input(input_name: String) -> VisualShaderNodeInput:
	var n := VisualShaderNodeInput.new()
	n.input_name = input_name
	return n


func float_param(pname: String, def: float, lo: float, hi: float) -> VisualShaderNodeFloatParameter:
	var n := VisualShaderNodeFloatParameter.new()
	n.parameter_name = pname
	n.hint = VisualShaderNodeFloatParameter.HINT_RANGE
	n.min = lo
	n.max = hi
	n.default_value_enabled = true
	n.default_value = def
	return n


func color_param(pname: String, def: Color) -> VisualShaderNodeColorParameter:
	var n := VisualShaderNodeColorParameter.new()
	n.parameter_name = pname
	n.default_value_enabled = true
	n.default_value = def
	return n


func float_const(v: float) -> VisualShaderNodeFloatConstant:
	var n := VisualShaderNodeFloatConstant.new()
	n.constant = v
	return n


func float_op(op: VisualShaderNodeFloatOp.Operator) -> VisualShaderNodeFloatOp:
	var n := VisualShaderNodeFloatOp.new()
	n.operator = op
	return n


func float_func(f: VisualShaderNodeFloatFunc.Function) -> VisualShaderNodeFloatFunc:
	var n := VisualShaderNodeFloatFunc.new()
	n.function = f
	return n


func vec_op(op: VisualShaderNodeVectorOp.Operator, op_type: VisualShaderNodeVectorOp.OpType) -> VisualShaderNodeVectorOp:
	var n := VisualShaderNodeVectorOp.new()
	n.op_type = op_type
	n.operator = op
	return n


func decompose(op_type: VisualShaderNodeVectorDecompose.OpType) -> VisualShaderNodeVectorDecompose:
	var n := VisualShaderNodeVectorDecompose.new()
	n.op_type = op_type
	return n


func compose(op_type: VisualShaderNodeVectorCompose.OpType) -> VisualShaderNodeVectorCompose:
	var n := VisualShaderNodeVectorCompose.new()
	n.op_type = op_type
	return n


func smoothstep_node() -> VisualShaderNodeSmoothStep:
	var n := VisualShaderNodeSmoothStep.new()
	n.op_type = VisualShaderNodeSmoothStep.OP_TYPE_SCALAR
	return n


func mix_node(op_type: VisualShaderNodeMix.OpType) -> VisualShaderNodeMix:
	var n := VisualShaderNodeMix.new()
	n.op_type = op_type
	return n


func texture(tex: Texture2D) -> VisualShaderNodeTexture:
	var n := VisualShaderNodeTexture.new()
	n.source = VisualShaderNodeTexture.SOURCE_TEXTURE
	n.texture = tex
	return n


func noise_texture(frequency: float, octaves: int, size := 256) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = noise
	return tex
