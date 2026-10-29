## VFX Forge 예제 레시피 생성기. addons/vfx_forge/recipes/*.vfx.json 을 다시 만든다.
##   Godot.exe --headless --path . --script res://tools/build_vfx_recipes.gd
## 레시피를 에디터에서 손으로 고쳤다면 다시 돌리지 마세요. 덮어써집니다.
extends SceneTree

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")
const OUT_DIR := "res://addons/vfx_forge/recipes"

var g: VfxForgeGraph


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	slash_arc()
	impact_burst()
	fire_loop()
	lightning_bolt()
	magic_circle()
	star_flare()
	shockwave()
	energy_orb()
	smoke_puff()
	trail_strip()
	caustics_tile()
	heal_sparkles()
	portal_swirl()
	quit()


# ---------------- 헬퍼 ----------------

func begin(name: String, settings := {}) -> void:
	g = VfxForgeGraph.new()
	g.name = name
	for k in settings:
		g.settings[k] = settings[k]
	g.settings.export_path = "res://vfx_textures/%s.png" % name


## params 는 JSON 형식 값 (색 "#rrggbbaa", vec2 [x, y], 그라데이션 [[위치, 색]...])
func n(type: String, x: float, y: float, params := {}) -> int:
	var id := g.add_node(type, Vector2(x, y))
	var def := Lib.get_def(type)
	for k in params:
		var p := Lib.find_param(def, k)
		assert(not p.is_empty(), "%s 에 %s 파라미터가 없음" % [type, k])
		g.nodes[id].params[k] = VfxForgeGraph.param_from_json(p, params[k])
	return id


## 출력 포트 이름을 생략하면 첫 출력
func link(from: int, to: int, to_port: String, from_port := "") -> void:
	if from_port == "":
		from_port = Lib.get_def(g.nodes[from].type).outputs[0].name
	var ok := g.connect_ports(from, from_port, to, to_port)
	assert(ok, "연결 실패 %d.%s -> %d.%s" % [from, from_port, to, to_port])


func finish(color_node: int, mode := 0) -> void:
	var out := n("output", 0, 0, {"mode": mode})
	var max_x := 0.0
	for id in g.nodes:
		max_x = maxf(max_x, g.nodes[id].pos.x)
	g.nodes[out].pos = Vector2(max_x + 300, 0)
	link(color_node, out, "color")
	_auto_layout()
	var path := OUT_DIR.path_join(g.name + ".vfx.json")
	var err := g.save(path)
	print("saved ", path, " err=", err, " nodes=", g.nodes.size())


## 의존 깊이(가장 긴 입력 경로)로 열을 나누고, 열 안에서는 원래 y 순서대로 겹치지 않게 쌓는다
func _auto_layout() -> void:
	var depth := {}
	for id in g.nodes:
		depth[id] = 0
	for _i in g.nodes.size():
		for c in g.connections:
			depth[c.to] = maxi(depth[c.to], depth[c.from] + 1)
	var cols := {}
	for id in g.nodes:
		if not cols.has(depth[id]):
			cols[depth[id]] = []
		cols[depth[id]].append(id)
	for d in cols:
		var ids: Array = cols[d]
		ids.sort_custom(func(a, b): return g.nodes[a].pos.y < g.nodes[b].pos.y)
		var y := 0.0
		for id in ids:
			g.nodes[id].pos = Vector2(d * 340, y)
			y += _est_height(id) + 30


func _est_height(id: int) -> float:
	var def := Lib.get_def(g.nodes[id].type)
	var h: float = 44.0 + (def.outputs.size() + def.inputs.size()) * 26.0
	for p in def.params:
		h += 34.0 if p.type in ["gradient", "enum"] else 26.0
	return h


## 0..1 을 lo..hi 로 (레벨 노드)
func rmap(x: int, lo: float, hi: float, px: float, py: float) -> int:
	var l := n("levels", px, py, {"out_min": lo, "out_max": hi})
	link(x, l, "x")
	return l


func ez(mode: int, start: float, end: float, power: float, px: float, py: float) -> int:
	return n("ease", px, py, {"mode": mode, "start": start, "end": end, "power": power})


func blend(a: int, b: int, mode: int, px: float, py: float, amount := 1.0, a_port := "", b_port := "") -> int:
	var bl := n("blend", px, py, {"mode": mode, "amount": amount})
	link(a, bl, "a", a_port)
	link(b, bl, "b", b_port)
	return bl


const MAX := 5
const MUL := 3
const ADD := 1
const SUB := 2
const EASE_OUT := 2
const PULSE := 6
const LINEAR := 0


# ---------------- 레시피 ----------------

## 검기 슬래시: 베지어 키 포즈 4개로 휘둘러 나갔다 사라지는 1회 재생 플립북
func slash_arc() -> void:
	begin("slash_arc", {"cols": 4, "rows": 4, "loop": false, "fps": 30.0})
	var arc := [[0.1, 0.74], [0.18, 0.14], [0.82, 0.14], [0.9, 0.74]]
	var bez := n("bezier", 0, 0, {
		"poses": [
			{"t": 0.0, "p": arc, "head": 0.02, "tail": 0.0, "width": 0.12},
			{"t": 0.3, "p": arc, "head": 1.0, "tail": 0.04, "width": 0.12},
			{"t": 0.65, "p": arc, "head": 1.0, "tail": 0.6, "width": 0.09},
			{"t": 1.0, "p": arc, "head": 1.0, "tail": 1.0, "width": 0.02},
		],
		"taper": 0.9, "peak": 0.78, "softness": 0.006,
	})
	# 곡선을 따라 흐르는 결: 곡선 좌표로 노이즈를 길게 늘인다
	var streak := n("noise", 300, 220, {"scale": 3.0, "stretch_y": 5.0, "octaves": 3.0, "seed": 4})
	link(bez, streak, "uv", "stroke_uv")
	var shade := n("levels", 300, -40, {"gamma": 0.55})
	link(bez, shade, "x", "across")
	var streaky := blend(shade, streak, MUL, 560, 60, 0.55)
	var val := blend(bez, streaky, MUL, 800, 0, 1.0, "mask")
	var gm := n("gradient_map", 1040, 0, {"gradient": [[0.0, "#2050ff00"], [0.08, "#2a6cffc0"], [0.3, "#48c8ffff"], [0.6, "#b8f4ffff"], [1.0, "#ffffffff"]]})
	link(val, gm, "x")
	finish(gm)


## 타격 임팩트: 빛줄기 + 충격 고리 + 튀는 파편 + 중심 섬광 (1회 재생)
func impact_burst() -> void:
	begin("impact_burst", {"cols": 4, "rows": 4, "loop": false, "fps": 30.0})
	var grow := ez(EASE_OUT, 0.0, 0.55, 3.0, 0, 0)
	var fade_in := ez(LINEAR, 0.15, 1.0, 1.0, 0, 200)
	var fade := n("math", 240, 200, {"op": 7})
	link(fade_in, fade, "a")
	# 고리
	var ring := n("circle", 520, -200, {"outline": true, "softness": 0.02})
	link(rmap(grow, 0.03, 0.44, 260, -260), ring, "radius")
	link(rmap(fade, 0.0, 0.07, 260, -120), ring, "thickness")
	# 빛줄기
	var rays := n("rays", 520, 60, {"count": 14.0, "jitter": 0.6, "softness": 0.02, "seed": 5})
	link(rmap(grow, 0.08, 0.3, 260, 0), rays, "len_min")
	link(rmap(grow, 0.15, 0.48, 260, 100), rays, "len_max")
	link(rmap(fade, 0.0, 0.045, 260, 300), rays, "width")
	# 파편
	var spark_t := ez(EASE_OUT, 0.0, 1.0, 2.0, 0, 420)
	var sparks := n("scatter", 520, 380, {"count": 20.0, "start_radius": 0.08, "travel": 0.4, "size": 0.012, "streak": 3.0, "fade": 1.2, "seed": 3})
	link(spark_t, sparks, "progress")
	# 중심 섬광
	var pulse := ez(PULSE, 0.0, 0.35, 1.0, 0, 620)
	var flash := n("circle", 520, 640, {"softness": 0.12})
	link(rmap(pulse, 0.0, 0.16, 260, 620), flash, "radius")
	var c1 := blend(ring, rays, MAX, 800, 0, 1.0, "mask")
	var c2 := blend(c1, sparks, MAX, 1000, 100)
	var c3 := blend(c2, flash, MAX, 1200, 200, 1.0, "", "mask")
	# 후반부에 전체가 주황 → 투명으로 식으며 사라진다
	var out_t := ez(LINEAR, 0.45, 1.0, 1.0, 1200, 420)
	var out_fade := n("math", 1420, 420, {"op": 7})
	link(out_t, out_fade, "a")
	var c4 := blend(c3, out_fade, MUL, 1420, 200)
	var gm := n("gradient_map", 1640, 200, {"gradient": [[0.0, "#ff3c0000"], [0.25, "#ff5a10e0"], [0.6, "#ffc040ff"], [1.0, "#fffbe8ff"]]})
	link(c4, gm, "x")
	finish(gm)


## 툰 불꽃 루프: 위로 흐르는 노이즈로 물방울 모양을 일렁이고 갉아먹은 뒤 색 띠를 딱딱 끊는다
func fire_loop() -> void:
	begin("fire_loop", {"cols": 4, "rows": 4, "loop": true, "fps": 20.0})
	var uv := n("uv", 0, 0)
	var sc1 := n("scroll", 200, -120, {"speed_x": 0.0, "speed_y": -2.0})
	link(uv, sc1, "uv")
	var nz1 := n("noise", 420, -120, {"scale": 4.0, "octaves": 4.0, "persistence": 0.55, "evolve": 1.0, "seed": 2})
	link(sc1, nz1, "uv")
	var sc2 := n("scroll", 200, 160, {"speed_x": 0.0, "speed_y": -3.0})
	link(uv, sc2, "uv")
	var nz2 := n("noise", 420, 160, {"scale": 6.0, "octaves": 3.0, "evolve": 1.0, "seed": 9})
	link(sc2, nz2, "uv")
	var warp := n("warp", 660, -120, {"strength": 0.2, "dir": 1})
	link(uv, warp, "uv")
	link(nz1, warp, "x")
	var tr := n("transform", 880, -120, {"scale_y": 1.7, "pivot": [0.5, 0.7]})
	link(warp, tr, "uv")
	var rad := n("gradient", 1100, -120, {"mode": 1, "center": [0.5, 0.7], "scale": 1.45})
	link(tr, rad, "uv")
	var shape := n("math", 1320, -120, {"op": 7})
	link(rad, shape, "a")
	# 위쪽일수록 많이 갉아먹는다
	var vert := n("gradient", 660, 300, {"mode": 0, "angle": 0.25})
	var top := n("math", 880, 300, {"op": 7})
	link(vert, top, "a")
	var ero := blend(nz2, top, MUL, 1100, 200)
	var field := blend(shape, ero, SUB, 1540, 0, 0.75)
	var gm := n("gradient_map", 1760, 0, {"gradient": [
		[0.0, "#e8301c00"], [0.3, "#e8301c00"], [0.31, "#d42a1cff"], [0.48, "#d42a1cff"], [0.49, "#ff7a1eff"],
		[0.64, "#ff7a1eff"], [0.65, "#ffc93cff"], [0.8, "#ffc93cff"], [0.81, "#fff4c4ff"], [1.0, "#fff4c4ff"]]})
	link(field, gm, "x")
	finish(gm)


## 번개: 2프레임마다 모양이 바뀌는 지그재그 + 가지 + 글로우
func lightning_bolt() -> void:
	begin("lightning_bolt", {"cols": 4, "rows": 4, "loop": true, "fps": 24.0})
	var lt := n("lightning", 0, 0, {"a": [0.44, 0.03], "b": [0.56, 0.97], "amplitude": 0.13, "frequency": 5.0, "width": 0.011, "glow": 0.035, "branches": 3.0, "flicker": 8.0, "seed": 3})
	var g2 := n("math", 260, 120, {"op": 2, "b": 0.6})
	link(lt, g2, "a", "glow")
	var val := blend(lt, g2, MAX, 500, 0, 1.0, "core")
	var gm := n("gradient_map", 740, 0, {"gradient": [[0.0, "#5a2cff00"], [0.2, "#6a3cff90"], [0.5, "#55c8ffff"], [0.8, "#c8f6ffff"], [1.0, "#ffffffff"]]})
	link(val, gm, "x")
	finish(gm)


## 마법진: 고리 + 룬 글자띠 + 육망성 + 눈금 + 글로우. 회전은 게임에서 노드를 돌리면 된다.
func magic_circle() -> void:
	begin("magic_circle", {"cols": 1, "rows": 1, "loop": false, "frame_size": 1024, "make_sprite_frames": false})
	var ring_o := n("circle", 0, 0, {"radius": 0.465, "outline": true, "thickness": 0.01, "softness": 0.003})
	var ring_2 := n("circle", 0, 200, {"radius": 0.4, "outline": true, "thickness": 0.005, "softness": 0.002})
	var runes := n("rune_ring", 0, 400, {"radius": 0.4325, "size": 0.042, "count": 32.0, "stroke": 0.0045, "density": 0.32, "softness": 0.002, "seed": 7})
	var hexa := n("polygon", 0, 640, {"radius": 0.375, "sides": 6.0, "star": 0.387, "outline": true, "thickness": 0.006, "softness": 0.002, "rotate": 0.0})
	var hexo := n("polygon", 0, 900, {"radius": 0.375, "sides": 6.0, "star": 0.0, "outline": true, "thickness": 0.004, "softness": 0.002, "rotate": 0.0833})
	var ring_i := n("circle", 0, 1140, {"radius": 0.215, "outline": true, "thickness": 0.005, "softness": 0.002})
	var runes_i := n("rune_ring", 0, 1340, {"radius": 0.18, "size": 0.032, "count": 14.0, "stroke": 0.0045, "density": 0.35, "softness": 0.002, "seed": 21})
	var kal := n("kaleido", -300, 1600, {"segments": 24.0, "mirror": true})
	var ticks := n("line", 0, 1600, {"a": [0.86, 0.5], "b": [0.895, 0.5], "width_a": 0.003, "width_b": 0.003, "softness": 0.002})
	link(kal, ticks, "uv")
	var core := n("polygon", 0, 1860, {"radius": 0.07, "sides": 4.0, "star": 0.75, "softness": 0.003})
	var b := blend(ring_o, ring_2, MAX, 300, 100)
	b = blend(b, runes, MAX, 500, 300)
	b = blend(b, hexa, MAX, 700, 500)
	b = blend(b, hexo, MAX, 900, 700)
	b = blend(b, ring_i, MAX, 1100, 900)
	b = blend(b, runes_i, MAX, 1300, 1100)
	b = blend(b, ticks, MAX, 1500, 1300)
	b = blend(b, core, MAX, 1700, 1500)
	# 글로우: 바깥 고리와 육망성 sdf 에서 퍼지는 빛
	var gl1 := n("glow", 300, -300, {"radius": 0.03, "intensity": 0.7})
	link(ring_o, gl1, "sdf", "sdf")
	var gl2 := n("glow", 300, -150, {"radius": 0.02, "intensity": 0.45})
	link(hexa, gl2, "sdf", "sdf")
	var gl := blend(gl1, gl2, MAX, 560, -220)
	var glow_c := n("colorize", 1900, -220, {"color": "#ff9a2aff", "intensity": 1.0})
	link(gl, glow_c, "mask")
	var line_c := n("colorize", 1900, 1500, {"color": "#fff1c2ff", "intensity": 1.0})
	link(b, line_c, "mask")
	var cb := n("color_blend", 2150, 600, {"mode": 0})
	link(glow_c, cb, "a")
	link(line_c, cb, "b")
	finish(cb)


## 별빛 플레어: 긴 십자 빛 + 잔빛줄기 + 부드러운 후광 + 코어 (단일 이미지)
func star_flare() -> void:
	begin("star_flare", {"cols": 1, "rows": 1, "loop": false, "make_sprite_frames": false})
	var long_r := n("rays", 0, 0, {"count": 4.0, "width": 0.014, "len_min": 0.48, "len_max": 0.5, "jitter": 0.0, "softness": 0.012, "rotate": 0.0})
	var diag := n("rays", 0, 260, {"count": 4.0, "width": 0.008, "len_min": 0.22, "len_max": 0.24, "jitter": 0.0, "softness": 0.01, "rotate": 0.125})
	var small := n("rays", 0, 520, {"count": 28.0, "width": 0.004, "len_min": 0.08, "len_max": 0.26, "jitter": 1.0, "softness": 0.006, "seed": 9})
	var halo := n("gradient", 0, 780, {"mode": 1, "scale": 1.6})
	var inv := n("math", 240, 780, {"op": 7})
	link(halo, inv, "a")
	var halo_p := n("math", 460, 780, {"op": 4, "b": 3.0})
	link(inv, halo_p, "a")
	var core := n("circle", 0, 1000, {"radius": 0.025, "softness": 0.06})
	var s1 := blend(long_r, diag, MAX, 300, 100)
	var s2 := blend(s1, small, MAX, 520, 300, 0.6)
	var s3 := blend(s2, halo_p, ADD, 740, 500, 0.8)
	var s4 := blend(s3, core, MAX, 960, 700, 1.0, "", "mask")
	var gm := n("gradient_map", 1180, 500, {"gradient": [[0.0, "#ffb04000"], [0.12, "#ff9a3070"], [0.45, "#ffd890ff"], [1.0, "#ffffffff"]]})
	link(s4, gm, "x")
	finish(gm)


## 충격파 고리: 빠르게 퍼지며 얇아지는 고리 (1회 재생)
func shockwave() -> void:
	begin("shockwave", {"cols": 4, "rows": 4, "loop": false, "fps": 30.0})
	var e := ez(EASE_OUT, 0.0, 1.0, 2.5, 0, 0)
	var nz := n("noise", 0, 200, {"scale": 6.0, "octaves": 2.0, "seed": 4})
	var warp := n("warp", 240, 200, {"strength": 0.035})
	link(nz, warp, "x")
	var ring := n("circle", 480, 0, {"outline": true, "softness": 0.03})
	link(warp, ring, "uv")
	link(rmap(e, 0.04, 0.46, 240, -160), ring, "radius")
	link(rmap(e, 0.16, 0.0, 240, 0), ring, "thickness")
	var gm := n("gradient_map", 720, 0, {"gradient": [[0.0, "#80d0ff00"], [0.4, "#80d0ff90"], [1.0, "#e8fbffff"]]})
	link(ring, gm, "x")
	finish(gm)


## 에너지 구슬: 소용돌이치는 셀 무늬 + 내부 빛 + 테두리 (루프)
func energy_orb() -> void:
	begin("energy_orb", {"cols": 4, "rows": 4, "loop": true, "fps": 20.0})
	var tw := n("twirl", 0, 0, {"strength": 0.35, "radius": 0.4})
	var vor := n("voronoi", 220, 0, {"scale": 6.0, "anim": 1.0, "jitter": 0.9, "seed": 2})
	link(tw, vor, "uv")
	var ed := n("levels", 440, 0, {"in_min": 0.0, "in_max": 0.12})
	link(vor, ed, "x", "edge")
	var lines := n("math", 660, 0, {"op": 7})
	link(ed, lines, "a")
	var inner := n("gradient", 220, 260, {"mode": 1, "scale": 1.5})
	var inner_i := n("math", 440, 260, {"op": 7})
	link(inner, inner_i, "a")
	var inner_p := n("math", 660, 260, {"op": 4, "b": 2.0})
	link(inner_i, inner_p, "a")
	var body := blend(lines, inner_p, ADD, 880, 100, 0.9)
	var sphere := n("circle", 660, 500, {"radius": 0.34, "softness": 0.03})
	var masked := blend(body, sphere, MUL, 1100, 200, 1.0, "", "mask")
	var rim := n("circle", 880, 500, {"radius": 0.34, "outline": true, "thickness": 0.02, "softness": 0.03})
	var all := blend(masked, rim, MAX, 1320, 300, 1.0, "", "mask")
	var gm := n("gradient_map", 1540, 300, {"gradient": [[0.0, "#4010a000"], [0.25, "#7a2cffb0"], [0.6, "#c070ffff"], [1.0, "#fff0ffff"]]})
	link(all, gm, "x")
	finish(gm)


## 연기 뭉치: 커지면서 흩어지는 툰 연기 (1회 재생)
func smoke_puff() -> void:
	begin("smoke_puff", {"cols": 4, "rows": 4, "loop": false, "fps": 20.0, "blend": "mix"})
	var e := ez(EASE_OUT, 0.0, 1.0, 2.0, 0, 0)
	var sc := n("scroll", 0, 200, {"speed_y": -1.0})
	var nz := n("noise", 220, 200, {"mode": 2, "scale": 4.0, "octaves": 4.0, "persistence": 0.5, "evolve": 1.0, "seed": 6})
	link(sc, nz, "uv")
	var warp := n("warp", 440, 200, {"strength": 0.22})
	link(nz, warp, "x")
	var blob := n("circle", 660, 0, {"softness": 0.2})
	link(warp, blob, "uv")
	link(rmap(e, 0.18, 0.42, 440, -120), blob, "radius")
	var field := blend(blob, nz, MUL, 880, 100, 0.5, "mask")
	var thr := n("step", 1100, 100, {"softness": 0.03})
	link(field, thr, "x")
	link(rmap(e, 0.18, 0.75, 880, 300), thr, "threshold")
	# 명암: 같은 필드를 툰 단계로
	var shade := n("posterize", 1100, -120, {"steps": 3.0})
	var shade_in := n("levels", 880, -120, {"in_min": 0.2, "in_max": 0.9})
	link(field, shade_in, "x")
	link(shade_in, shade, "x")
	var gm := n("gradient_map", 1320, -120, {"gradient": [[0.0, "#3c3c48ff"], [0.5, "#74748aff"], [1.0, "#c4c4d4ff"]]})
	link(shade, gm, "x")
	var sa := n("set_alpha", 1540, 0)
	link(gm, sa, "color")
	link(thr, sa, "alpha")
	finish(sa)


## 트레일 띠: 가로로 이음새 없이 반복되는 결 (Line2D/메시 트레일용)
func trail_strip() -> void:
	begin("trail_strip", {"cols": 1, "rows": 1, "loop": false, "usage": "strip", "make_sprite_frames": false, "make_particle_material": false})
	var nz := n("noise", 0, 0, {"scale": 3.0, "stretch_y": 4.0, "octaves": 3.0, "persistence": 0.5, "seed": 12})
	var vert := n("gradient", 0, 260, {"mode": 0, "angle": 0.25})
	var band := n("band", 220, 260, {"center": 0.5, "width": 0.25, "softness": 0.35})
	link(vert, band, "x")
	var lv := n("levels", 220, 0, {"in_min": 0.25, "in_max": 0.8})
	link(nz, lv, "x")
	var val := blend(band, lv, MUL, 440, 100, 0.7)
	var gm := n("gradient_map", 660, 100, {"gradient": [[0.0, "#3080ff00"], [0.3, "#3a8cffa0"], [0.7, "#7fe0ffff"], [1.0, "#ffffffff"]]})
	link(val, gm, "x")
	finish(gm)


## 물결 커스틱: 상하좌우로 반복되는 타일 + 루프 애니메이션 (바닥/수면 텍스처)
func caustics_tile() -> void:
	begin("caustics_tile", {"cols": 4, "rows": 4, "loop": true, "usage": "tile", "frame_size": 256, "fps": 12.0, "blend": "mix", "make_particle_material": false})
	var v1 := n("voronoi", 0, 0, {"scale": 4.0, "anim": 1.0, "seed": 3})
	var v2 := n("voronoi", 0, 260, {"scale": 6.0, "anim": 1.0, "seed": 8})
	var e1 := n("levels", 220, 0, {"in_min": 0.0, "in_max": 0.15})
	link(v1, e1, "x", "edge")
	var e2 := n("levels", 220, 260, {"in_min": 0.0, "in_max": 0.12})
	link(v2, e2, "x", "edge")
	var i1 := n("math", 440, 0, {"op": 7})
	link(e1, i1, "a")
	var i2 := n("math", 440, 260, {"op": 7})
	link(e2, i2, "a")
	var p1 := n("math", 660, 0, {"op": 4, "b": 2.0})
	link(i1, p1, "a")
	var p2 := n("math", 660, 260, {"op": 4, "b": 2.0})
	link(i2, p2, "a")
	var val := blend(p1, p2, ADD, 880, 100, 0.7)
	var gm := n("gradient_map", 1100, 100, {"gradient": [[0.0, "#0a4a7aff"], [0.45, "#2f9ad0ff"], [1.0, "#e8fbffff"]]})
	link(val, gm, "x")
	finish(gm)


## 회복 반짝이: 아래에서 위로 올라가는 빛 입자. 반 주기 어긋난 두 무리로 끊김 없이 루프
func heal_sparkles() -> void:
	begin("heal_sparkles", {"cols": 4, "rows": 4, "loop": true, "fps": 20.0})
	var t := n("time", 0, 0)
	var t2 := n("math", 220, 200, {"op": 0, "b": 0.5})
	link(t, t2, "a")
	var t2f := n("math", 440, 200, {"op": 10})
	link(t2, t2f, "a")
	var common := {"center": [0.5, 0.88], "count": 18.0, "direction": 0.75, "spread": 0.14, "start_radius": 0.02, "travel": 0.8, "size": 0.032, "size_random": 0.6, "streak": 0.8, "fade": 1.2}
	var s1p := common.duplicate()
	s1p.seed = 1
	var s2p := common.duplicate()
	s2p.seed = 2
	var s1 := n("scatter", 660, 0, s1p)
	link(t, s1, "progress")
	var s2 := n("scatter", 660, 300, s2p)
	link(t2f, s2, "progress")
	var both := blend(s1, s2, MAX, 900, 100)
	var gm := n("gradient_map", 1120, 100, {"gradient": [[0.0, "#40ff8000"], [0.35, "#40ff80c0"], [1.0, "#e8ffe8ff"]]})
	link(both, gm, "x")
	finish(gm)


## 포털 소용돌이: 극좌표로 돌며 빨려 들어가는 노이즈 고리 (루프)
func portal_swirl() -> void:
	begin("portal_swirl", {"cols": 4, "rows": 4, "loop": true, "fps": 20.0})
	var tw := n("twirl", 0, 0, {"strength": 0.6, "radius": 0.7})
	var pol := n("polar", 220, 0, {"mode": 0})
	link(tw, pol, "uv")
	var sc := n("scroll", 440, 0, {"speed_x": 1.0, "speed_y": 1.0})
	link(pol, sc, "uv")
	var nz := n("noise", 660, 0, {"scale": 6.0, "stretch_y": 0.5, "octaves": 4.0, "evolve": 1.0, "wrap_x": true, "seed": 5})
	link(sc, nz, "uv")
	var rad := n("gradient", 440, 280, {"mode": 1, "scale": 1.0})
	var ring := n("band", 660, 280, {"center": 0.62, "width": 0.3, "softness": 0.3})
	link(rad, ring, "x")
	var hole := n("circle", 660, 520, {"radius": 0.13, "softness": 0.12})
	var val := blend(nz, ring, MUL, 880, 100)
	var lv := n("levels", 1100, 100, {"in_min": 0.1, "in_max": 0.75})
	link(val, lv, "x")
	var gm := n("gradient_map", 1320, 100, {"gradient": [[0.0, "#20084000"], [0.25, "#5a1ca8c0"], [0.55, "#a040ffff"], [0.8, "#40e0ffff"], [1.0, "#e8ffffff"]]})
	link(lv, gm, "x")
	# 가운데 어두운 구멍
	var hole_c := n("colorize", 1320, 400, {"color": "#0a0418ff"})
	link(hole, hole_c, "mask")
	var cb := n("color_blend", 1540, 200, {"mode": 0, "amount": 0.9})
	link(gm, cb, "a")
	link(hole_c, cb, "b")
	finish(cb)
