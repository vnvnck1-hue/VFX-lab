## VFX Forge 자기 점검: 패널 UI 동작(열기/선택/키 포즈/연결/실행 취소/저장/이음새 검사)을 자동으로 확인한다.
##   Godot.exe --path . --script res://tools/vfx_forge_selftest.gd -- <스크린샷 폴더(생략 가능)>
extends SceneTree
var S: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
func _initialize():
	root.size = Vector2i(1600, 900)
	_go.call_deferred()
func shot(name):
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(S.path_join(name))
func check(cond, msg):
	print(("PASS " if cond else "FAIL ") + msg)
func _go():
	var p := VfxForgePanel.new()
	root.add_child(p)
	await process_frame
	# 1. 레시피 열기
	check(p.open_recipe("res://addons/vfx_forge/recipes/slash_arc.vfx.json"), "open slash_arc")
	check(p.current_path == "", "example recipe opens without path (save-as)")
	# 2. 베지어 노드 선택 → 키 포즈 패널
	var bez := -1
	for id in p.graph.nodes:
		if p.graph.nodes[id].type == "bezier": bez = id
	p.graph_edit.set_selected(p._view(bez))
	await process_frame
	check(p.bezier_box.visible, "bezier box visible on select")
	check(p.key_list.item_count == 4, "4 keys listed")
	p._set_playing(false)
	p._set_frame(6)
	await shot("ui_slash.png")
	# 3. 키 포즈 드래그 → 키 자동 추가
	var before: int = p._keys().size()
	p._on_bezier_point_dragged(1, Vector2(0.3, 0.05), true)
	check(p._keys().size() == before + 1, "drag on non-key frame adds key")
	p._undo_action()
	check(p.graph.nodes[bez].params.poses.size() == before, "undo removes added key")
	p._redo_action()
	check(p.graph.nodes[bez].params.poses.size() == before + 1, "redo re-adds key")
	# 4. 노드 추가 + 연결 + 파라미터
	var n_before := p.graph.nodes.size()
	p._add_graph_pos = Vector2(100, 600)
	p._on_add_menu_id(p._menu_types.find("noise"))
	check(p.graph.nodes.size() == n_before + 1, "add node via menu")
	var nid: int = p.graph.next_id - 1
	var gm := -1
	for id in p.graph.nodes:
		if p.graph.nodes[id].type == "gradient_map": gm = id
	p._on_connection_request(str(nid), 0, str(gm), p._view(gm).in_ports.find("x"))
	check(p.graph.input_connection(gm, "x").get("from", -1) == nid, "connect noise -> gradient_map.x")
	p._on_param_changed(nid, "scale", 9.0, true)
	check(is_equal_approx(p.graph.nodes[nid].params.scale, 9.0), "param change")
	p._undo_action()
	check(is_equal_approx(p.graph.nodes[nid].params.scale, 4.0), "undo param")
	# 순환 연결 거부
	var out := p.graph.output_node()
	p._on_connection_request(str(gm), 0, str(nid), p._view(nid).in_ports.find("scale"))
	check(p.graph.input_connection(nid, "scale").is_empty(), "cycle rejected")
	# 5. 삭제
	p._on_delete_nodes([StringName(str(nid))])
	check(not p.graph.nodes.has(nid), "delete node")
	p._on_delete_nodes([StringName(str(out))])
	check(p.graph.nodes.has(out), "output node protected")
	# 6. 시트 미리보기 + 저장/불러오기 왕복
	p.preview_mode_opt.select(1)
	p._update_preview_size()
	await shot("ui_sheet.png")
	var tmp := "user://_t.vfx.json"
	p._save_to(tmp)
	var g2 := VfxForgeGraph.load_file(tmp)
	check(g2 != null and g2.to_json() == p.graph.to_json(), "save/load roundtrip")
	# 7. 이음새 검사: 타일 레시피는 통과, 그라데이션은 원인으로 지목
	p.open_recipe("res://addons/vfx_forge/recipes/caustics_tile.vfx.json")
	var r: Dictionary = await VfxForgeExporter.check_seams(p.renderer, p.graph)
	check(r.ok, "caustics seamless: " + r.message)
	var g := VfxForgeGraph.new()
	g.settings.usage = "tile"
	g.settings.cols = 1
	g.settings.rows = 1
	var gr := g.add_node("gradient", Vector2.ZERO)
	g.nodes[gr].params.mode = 0
	var o := g.add_node("output", Vector2(300, 0))
	g.connect_ports(gr, "value", o, "color")
	p.load_graph(g, "")
	r = await VfxForgeExporter.check_seams(p.renderer, p.graph)
	check(not r.ok and r.node == gr, "linear gradient flagged: " + r.message)
	p.preview_mode_opt.select(0)
	p.open_recipe("res://addons/vfx_forge/recipes/fire_loop.vfx.json")
	await shot("ui_fire.png")
	quit()
