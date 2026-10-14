## 스타일라이즈드 불꽃(2D) VisualShader 생성기.
## 텍스처 한 장 없이 노이즈 + 거리장(SDF 비슷한 field)으로 물방울 모양 불꽃을 만든다.
## 실행: Godot.exe --headless --path . --script res://tools/build_flame_shader.gd
##
## 원리
##   1) 둥근 바닥 + 위로 길게 늘어진 물방울 모양 거리장 field (안쪽 > 0)
##   2) 위로 흐르는 노이즈 A 로 x 좌표를 흔들어 일렁임 (위쪽일수록 강하게)
##   3) 위로 흐르는 노이즈 B 를 field 에서 빼서 갉아먹음 → 위쪽이 찢어져 떨어지는 덩어리
##   4) field 를 smoothstep 으로 단계 나눔: 몸통(알파) / 테두리 림 / 흰 코어 / 바깥 글로우
##   5) 세로 그라데이션 시안 → 보라
extends SceneTree

const VSBuilder := preload("res://tools/vs_builder.gd")
const SHADER_PATH := "res://vfx/flame/flame.tres"
const MATERIAL_PATH := "res://vfx/flame/flame_material.tres"

const ADD := VisualShaderNodeFloatOp.OP_ADD
const SUB := VisualShaderNodeFloatOp.OP_SUB
const MUL := VisualShaderNodeFloatOp.OP_MUL
const DIV := VisualShaderNodeFloatOp.OP_DIV
const MAX := VisualShaderNodeFloatOp.OP_MAX


func _init() -> void:
	var b := VSBuilder.new(VisualShader.MODE_CANVAS_ITEM)
	b.vs.set("flags/unshaded", true)  # 2D 조명/CanvasModulate 에 어두워지지 않는 발광체
	var P := func(x: float, y: float) -> Vector2: return Vector2(x, y)

	# ---------- 파라미터 ----------
	var speed := b.add(b.float_param("scroll_speed", 0.55, 0.0, 3.0), -3000, -600)
	var time_offset := b.add(b.float_param("time_offset", 0.0, 0.0, 100.0), -3000, -500)
	var distort := b.add(b.float_param("distortion", 0.8, 0.0, 1.0), -3000, -400)
	var aspect := b.add(b.float_param("aspect", 0.5, 0.1, 2.0), -3000, -300)
	var taper := b.add(b.float_param("taper", 1.0, 0.0, 5.0), -3000, -200)
	var center_y := b.add(b.float_param("center_y", 0.76, 0.0, 1.0), -3000, -100)
	var stretch := b.add(b.float_param("stretch", 0.24, 0.05, 1.0), -3000, 0)
	var radius := b.add(b.float_param("radius", 0.15, 0.01, 0.5), -3000, 100)
	var erosion := b.add(b.float_param("erosion", 1.0, 0.0, 3.0), -3000, 200)
	var softness := b.add(b.float_param("edge_softness", 0.01, 0.001, 0.3), -3000, 300)
	var rim_width := b.add(b.float_param("rim_width", 0.12, 0.0, 0.5), -3000, 400)
	var core_th := b.add(b.float_param("core_threshold", 0.25, 0.0, 1.0), -3000, 500)
	var glow_width := b.add(b.float_param("glow_width", 0.45, 0.0, 2.0), -3000, 600)
	var glow_alpha := b.add(b.float_param("glow_alpha", 0.55, 0.0, 1.0), -3000, 700)
	var c_bottom := b.add(b.color_param("bottom_color", Color(0.3, 0.9, 1.0)), -3000, 850)
	var c_top := b.add(b.color_param("top_color", Color(0.48, 0.3, 1.0)), -3000, 1000)
	var c_core := b.add(b.color_param("core_color", Color(0.93, 1.0, 1.0)), -3000, 1150)
	var c_glow := b.add(b.color_param("glow_color", Color(0.45, 0.3, 1.0)), -3000, 1300)

	# ---------- 좌표 ----------
	var uv := b.add(b.input("uv"), -2700, -900)
	var uv_d := b.node_with(b.decompose(VisualShaderNodeVectorDecompose.OP_TYPE_VECTOR_2D), [uv], P.call(-2500, -900))
	var u := Vector2i(uv_d, 0)
	var v := Vector2i(uv_d, 1)
	var up := b.fop(SUB, 1.0, v, P.call(-2300, -800))  # 아래 0 → 위 1

	var time := b.add(b.input("time"), -2700, -700)
	var t := b.fop(ADD, time, time_offset, P.call(-2500, -700))
	var scroll := b.fop(MUL, t, speed, P.call(-2300, -700))

	# ---------- 노이즈 A: 일렁임 (위로 흐름) ----------
	# 가로 샘플 위치 = time_offset 으로 인스턴스마다 다른 영역 + 느린 옆 드리프트(노이즈가 fract 로 1 주기라 세로 스크롤만으론 금방 반복됨)
	var na_shift := b.fop(ADD, b.fop(MUL, time_offset, 0.37, P.call(-2500, -1100)), b.fop(MUL, scroll, 0.05, P.call(-2500, -1000)), P.call(-2300, -1050))
	var na_u := b.fop(ADD, b.fop(MUL, u, 0.3, P.call(-2100, -1100)), na_shift, P.call(-2100, -1000))
	var na_v := b.fop(ADD, b.fop(MUL, v, 0.6, P.call(-2100, -900)), scroll, P.call(-1900, -900))
	var na := b.sample_r(b.texture(b.noise_texture(0.008, 2)), b.vec2(na_u, na_v, P.call(-1700, -950)), P.call(-1500, -950))
	var na_c := b.fop(SUB, Vector2i(na, 0), 0.5, P.call(-1100, -950))  # -0.5 ~ 0.5

	# ---------- 노이즈 B: 갉아먹기 (더 빠르게 위로) ----------
	var nb_shift := b.fop(ADD, b.fop(MUL, time_offset, 0.61, P.call(-2500, -600)), b.fop(MUL, scroll, 0.15, P.call(-2500, -500)), P.call(-2300, -550))
	var nb_u := b.fop(ADD, b.fop(MUL, u, 0.55, P.call(-2100, -500)), nb_shift, P.call(-1900, -500))
	var nb_v := b.fop(ADD, b.fop(MUL, v, 1.1, P.call(-2100, -400)), b.fop(MUL, scroll, 1.6, P.call(-2100, -300)), P.call(-1900, -400))
	var nb := b.sample_r(b.texture(b.noise_texture(0.014, 3)), b.vec2(nb_u, nb_v, P.call(-1700, -450)), P.call(-1500, -450))

	# ---------- 물방울 거리장 ----------
	# x = u + na * distortion * (up + 0.25)   : 위로 갈수록 크게, 바닥도 살짝 흔들려 몸통 전체가 S자로 휨
	var sway := b.fop(ADD, up, 0.25, P.call(-900, -850))
	var wobble := b.fop(MUL, b.fop(MUL, na_c, distort, P.call(-900, -950)), sway, P.call(-700, -950))
	var x := b.fop(ADD, u, wobble, P.call(-500, -950))
	# dx = (x - 0.5) * aspect * (1 + up * taper)   : 위로 갈수록 좁아짐
	var narrow := b.fop(ADD, b.fop(MUL, up, taper, P.call(-700, -800)), 1.0, P.call(-500, -800))
	var dx := b.fop(MUL, b.fop(MUL, b.fop(SUB, x, 0.5, P.call(-300, -950)), aspect, P.call(-100, -950)), narrow, P.call(100, -900))
	# dy = (v - center_y) * (중심 위쪽이면 stretch, 아래쪽이면 1)  : 바닥은 둥글고 위는 길게
	var above := b.sstep(b.fop(ADD, center_y, 0.05, P.call(-700, -650)), b.fop(SUB, center_y, 0.05, P.call(-700, -550)), v, P.call(-500, -600))
	var y_scale := b.mixf(1.0, stretch, above, P.call(-300, -600))
	var dy := b.fop(MUL, b.fop(SUB, v, center_y, P.call(-300, -700)), y_scale, P.call(-100, -650))
	var dist := b.len2(b.vec2(dx, dy, P.call(300, -800)), P.call(500, -800))
	var field := b.fop(SUB, 1.0, b.fop(DIV, dist, radius, P.call(700, -800)), P.call(900, -800))
	# field -= nb * erosion * (up + 0.1)   : 위쪽일수록 많이 갉아먹힘
	var erode_amt := b.fop(MUL, b.fop(MUL, Vector2i(nb, 0), erosion, P.call(700, -450)), b.fop(ADD, up, 0.1, P.call(700, -350)), P.call(900, -400))
	var f := b.fop(SUB, field, erode_amt, P.call(1100, -600))

	# ---------- 단계 나누기 ----------
	var body := b.sstep(0.0, softness, f, P.call(1400, -800))
	var rim_in := b.sstep(softness, b.fop(ADD, softness, rim_width, P.call(1300, -650)), f, P.call(1500, -650))
	var rim := b.ffunc(VisualShaderNodeFloatFunc.FUNC_ONEMINUS, rim_in, P.call(1700, -650))
	var core_f := b.fop(ADD, f, b.fop(MUL, na_c, 0.5, P.call(1300, -500)), P.call(1500, -500))  # 코어는 조금 더 일렁이게
	var core := b.sstep(core_th, b.fop(ADD, core_th, softness, P.call(1500, -400)), core_f, P.call(1700, -450))
	var glow_lin := b.sstep(b.ffunc(VisualShaderNodeFloatFunc.FUNC_NEGATE, glow_width, P.call(1300, -250)), 0.0, f, P.call(1500, -250))
	var glow := b.fop(MUL, glow_lin, glow_lin, P.call(1700, -250))  # 제곱으로 부드럽게 감쇠

	# ---------- 색 ----------
	var grad := b.sstep(0.15, 0.7, b.fop(ADD, up, b.fop(MUL, na_c, 0.4, P.call(1300, 0)), P.call(1500, 0)), P.call(1700, 0))
	var col := b.mix3(c_bottom, c_top, grad, P.call(1900, 100))
	col = b.mix3(col, c_top, b.fop(MUL, rim, 0.85, P.call(1900, -650)), P.call(2100, 100))  # 테두리는 보라로
	col = b.mix3(col, c_core, core, P.call(2300, 100))
	var final_col := b.mix3(c_glow, col, body, P.call(2500, 100))
	var alpha := b.fop(MAX, body, b.fop(MUL, glow, glow_alpha, P.call(2300, -250)), P.call(2500, -250))

	b.link(final_col, 0, 0, "COLOR.rgb")
	b.link(alpha, 0, 0, "COLOR.a")
	b.save(SHADER_PATH)

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	if ResourceSaver.save(mat, MATERIAL_PATH) != OK:
		push_error("save failed: " + MATERIAL_PATH)

	print(b.vs.get_code())
	quit()
