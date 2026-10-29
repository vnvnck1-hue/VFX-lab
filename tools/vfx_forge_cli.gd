## VFX Forge 명령줄 도구 (GPU 렌더링이 필요해서 --headless 없이 실행한다).
##
##   레시피 일괄 내보내기 (레시피의 export_path 로):
##     Godot.exe --path . --script res://tools/vfx_forge_cli.gd -- --recipes=all
##   다른 폴더에 시트 PNG 만 저장 (프로젝트는 건드리지 않음):
##     Godot.exe --path . --script res://tools/vfx_forge_cli.gd -- --recipes=all --out-dir=C:/tmp/sheets
##   모든 노드 타입 컴파일/렌더 점검:
##     Godot.exe --path . --script res://tools/vfx_forge_cli.gd -- --test-nodes --out-dir=C:/tmp/nodes
extends SceneTree

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")
const RECIPE_DIR := "res://addons/vfx_forge/recipes"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var renderer := VfxForgeRenderer.new()
	root.add_child(renderer)
	await process_frame
	var out_dir: String = args.get("out-dir", "")
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)

	if args.has("test-nodes"):
		await _test_nodes(renderer, out_dir)
	if args.has("recipes"):
		await _export_recipes(renderer, str(args.recipes), out_dir)
	quit()


func _test_nodes(renderer: VfxForgeRenderer, out_dir: String) -> void:
	for type in Lib.NODES:
		if type == "output":
			continue
		var g := VfxForgeGraph.new()
		g.settings.frame_size = 256
		g.settings.cols = 2
		g.settings.rows = 2
		var id := g.add_node(type, Vector2.ZERO)
		var out := g.add_node("output", Vector2(300, 0))
		var def := Lib.get_def(type)
		g.connect_ports(id, def.outputs[0].name, out, "color")
		# 입력이 필요한 노드에는 그라데이션을 꽂아서 뭔가 보이게 한다
		for inp in def.inputs:
			if inp.type == Lib.FLOAT:
				var gr := g.add_node("gradient", Vector2(-300, 0))
				g.connect_ports(gr, "value", id, inp.name)
			elif inp.type == Lib.COLOR:
				var gr := g.add_node("gradient", Vector2(-300, 0))
				g.connect_ports(gr, "value", id, inp.name)
		renderer.set_graph(g)
		var img: Image = await renderer.render_image()
		var stats := _stats(img)
		print("[node] %-14s alpha_mean=%.3f lum_mean=%.3f" % [type, stats.x, stats.y])
		if out_dir != "":
			img.save_png(out_dir.path_join("node_%s.png" % type))


func _export_recipes(renderer: VfxForgeRenderer, which: String, out_dir: String) -> void:
	var paths := []
	if which == "all":
		for f in DirAccess.get_files_at(RECIPE_DIR):
			if f.ends_with(".vfx.json"):
				paths.append(RECIPE_DIR.path_join(f))
	else:
		paths = Array(which.split(","))
	for p in paths:
		var g := VfxForgeGraph.load_file(p)
		if g == null:
			push_error("레시피를 읽지 못했습니다: " + p)
			continue
		renderer.set_graph(g)
		if out_dir != "":
			var img: Image = await renderer.render_image()
			var out_png := out_dir.path_join(p.get_file().trim_suffix(".vfx.json") + ".png")
			img.save_png(out_png)
			var st := _stats(img)
			print("[recipe] %s -> %s (%dx%d) alpha_mean=%.3f" % [p.get_file(), out_png, img.get_width(), img.get_height(), st.x])
			if g.tiling() != Vector2.ZERO:
				var seam: Dictionary = await VfxForgeExporter.check_seams(renderer, g)
				print("    seams: ", seam.message)
		else:
			var res: Dictionary = await VfxForgeExporter.export_graph(renderer, g)
			print("[recipe] %s -> %s" % [p.get_file(), res])


func _stats(img: Image) -> Vector2:
	var a := 0.0
	var l := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			a += c.a
			l += c.get_luminance()
			n += 1
	return Vector2(a / n, l / n)
