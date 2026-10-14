## Dissolve VisualShader 생성기.
## Unity Shader Graph 의 "Dissolve" 예제를 Godot VisualShader 노드로 똑같이 조립해 .tres 로 저장한다.
## 실행: Godot.exe --headless --path . --script res://tools/build_dissolve_shader.gd
## 저장된 dissolve.tres 를 에디터에서 열면 노드 그래프로 보이고, 이후엔 에디터에서 직접 수정하면 된다.
extends SceneTree

const VSBuilder := preload("res://tools/vs_builder.gd")
const SHADER_PATH := "res://vfx/dissolve/dissolve.tres"
const MATERIAL_PATH := "res://vfx/dissolve/dissolve_material.tres"


func _init() -> void:
	var b := VSBuilder.new(VisualShader.MODE_SPATIAL)

	# ---------- 파라미터 (Shader Graph 의 Blackboard 프로퍼티) ----------
	var p_base := b.add(b.color_param("base_color", Color(0.15, 0.55, 0.9)), -1400, -300)
	var p_dissolve := b.add(b.float_param("dissolve_amount", 0.0, 0.0, 1.0), -1400, 100)
	var p_edge_width := b.add(b.float_param("edge_width", 0.08, 0.0, 0.5), -1400, 300)
	var p_edge_color := b.add(b.color_param("edge_color", Color(1.0, 0.45, 0.1)), -700, 500)
	var p_edge_intensity := b.add(b.float_param("edge_intensity", 6.0, 0.0, 20.0), -700, 700)
	var p_tiling := b.add(b.float_param("noise_tiling", 2.0, 0.1, 10.0), -1700, -50)

	# ---------- 노이즈 샘플링: Texture(UV * tiling).r ----------
	var uv := b.add(b.input("uv"), -1700, -150)
	var uv_mul := b.add(b.vec_op(VisualShaderNodeVectorOp.OP_MUL, VisualShaderNodeVectorOp.OP_TYPE_VECTOR_2D), -1450, -120)
	b.link(uv, 0, uv_mul, 0)
	b.link(p_tiling, 0, uv_mul, 1)

	var n_tex := b.add(b.texture(b.noise_texture(0.02, 4)), -1200, -150)
	b.link(uv_mul, 0, n_tex, 0)

	var n_dec := b.add(b.decompose(VisualShaderNodeVectorDecompose.OP_TYPE_VECTOR_4D), -950, -150)
	b.link(n_tex, 0, n_dec, 0)  # 출력 0 = x(=r) 채널이 노이즈 값

	# ---------- 가장자리 밴드: 1 - smoothstep(d, d + w, noise) ----------
	var add_w := b.add(b.float_op(VisualShaderNodeFloatOp.OP_ADD), -1150, 200)
	b.link(p_dissolve, 0, add_w, 0)
	b.link(p_edge_width, 0, add_w, 1)

	var n_smooth := b.add(b.smoothstep_node(), -700, 100)
	b.link(p_dissolve, 0, n_smooth, 0)  # edge0
	b.link(add_w, 0, n_smooth, 1)        # edge1
	b.link(n_dec, 0, n_smooth, 2)        # x

	var n_edge := b.add(b.float_func(VisualShaderNodeFloatFunc.FUNC_ONEMINUS), -450, 100)
	b.link(n_smooth, 0, n_edge, 0)

	# ---------- Emission = edge_color * edge * intensity ----------
	var edge_x_int := b.add(b.float_op(VisualShaderNodeFloatOp.OP_MUL), -250, 300)
	b.link(n_edge, 0, edge_x_int, 0)
	b.link(p_edge_intensity, 0, edge_x_int, 1)

	var emis := b.add(b.vec_op(VisualShaderNodeVectorOp.OP_MUL, VisualShaderNodeVectorOp.OP_TYPE_VECTOR_3D), 0, 300)
	b.link(p_edge_color, 0, emis, 0)
	b.link(edge_x_int, 0, emis, 1)

	# ---------- Albedo = base_color * (1 - edge) : 타는 부분은 검게 ----------
	var albedo := b.add(b.vec_op(VisualShaderNodeVectorOp.OP_MUL, VisualShaderNodeVectorOp.OP_TYPE_VECTOR_3D), 0, -300)
	b.link(p_base, 0, albedo, 0)
	var n_inv_edge := b.add(b.float_func(VisualShaderNodeFloatFunc.FUNC_ONEMINUS), -250, -150)
	b.link(n_edge, 0, n_inv_edge, 0)
	b.link(n_inv_edge, 0, albedo, 1)

	# ---------- Output (Shader Graph 의 Master Stack) ----------
	b.link(albedo, 0, 0, "ALBEDO")
	b.link(emis, 0, 0, "EMISSION")
	b.link(n_dec, 0, 0, "ALPHA")                         # Alpha = noise
	b.link(p_dissolve, 0, 0, "ALPHA_SCISSOR_THRESHOLD")  # Alpha Clip Threshold = dissolve
	b.save(SHADER_PATH)

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	if ResourceSaver.save(mat, MATERIAL_PATH) != OK:
		push_error("save failed: " + MATERIAL_PATH)

	print(b.vs.get_code())
	quit()
