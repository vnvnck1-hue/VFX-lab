## VFX Forge 메인 화면. 에디터 플러그인(메인 화면 탭)과 단독 실행 씬 양쪽에서 쓴다.
@tool
class_name VfxForgePanel
extends Control

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")
const RECIPE_DIR := "res://addons/vfx_forge/recipes"
const USER_RECIPE_DIR := "res://vfx_recipes"
const PREVIEW_MAX := 1024

## 내보내기가 끝났을 때 (에디터 플러그인이 파일시스템을 갱신한다)
signal exported(result: Dictionary)

var graph: VfxForgeGraph
var current_path := ""
var dirty := false
var renderer: VfxForgeRenderer

var graph_edit: GraphEdit
var preview: VfxForgePreviewView
var timeline: HSlider
var frame_label: Label
var play_button: Button
var status_label: Label
var title_label: Label
var add_menu: PopupMenu
var recipe_menu: MenuButton
var preview_mode_opt: OptionButton
var preview_selected_cb: CheckBox
var bg_opt: OptionButton
var file_dialog: FileDialog

# 설정 컨트롤
var size_opt: OptionButton
var cols_spin: SpinBox
var rows_spin: SpinBox
var loop_cb: CheckBox
var usage_opt: OptionButton
var import_opt: OptionButton
var fps_spin: SpinBox
var blend_opt: OptionButton
var path_edit: LineEdit
var frames_cb: CheckBox
var particle_cb: CheckBox
var sheet_info: Label

# 베지어 키 포즈
var bezier_box: VBoxContainer
var key_list: ItemList
var key_sliders := {}

var _playing := true
var _play_time := 0.0
var _frame := 0
var _selected_id := -1
var _bezier_node := -1
var _bezier_key := -1
var _busy := false
var _undo: Array[String] = []
var _redo: Array[String] = []
var _last_snapshot := ""
var _pending_link := {}
var _add_graph_pos := Vector2.ZERO
var _file_mode := ""
var _menu_types: Array[String] = []
var _updating_ui := false


func _ready() -> void:
	_build_ui()
	renderer = VfxForgeRenderer.new()
	add_child(renderer)
	preview.texture = renderer.get_texture()
	load_graph(VfxForgeGraph.create_default(), "")
	_status("새 레시피. 오른쪽 위 '예제 레시피'에서 시작하거나, 그래프에서 우클릭해 노드를 추가하세요.")


# ======================================================================
# UI 구성
# ======================================================================

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ---- 툴바 ----
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_tool_button(bar, "새로 만들기", _on_new, "기본 노드 몇 개로 새 레시피를 시작합니다")
	_tool_button(bar, "열기", func(): _open_dialog("open"), "레시피(.vfx.json)를 엽니다")
	recipe_menu = MenuButton.new()
	recipe_menu.text = "예제 레시피 ▾"
	recipe_menu.flat = false
	recipe_menu.tooltip_text = "포함된 예제 레시피에서 시작합니다 (원본은 바뀌지 않음)"
	recipe_menu.about_to_popup.connect(_fill_recipe_menu)
	recipe_menu.get_popup().id_pressed.connect(_on_recipe_menu)
	bar.add_child(recipe_menu)
	_tool_button(bar, "저장", _on_save, "Ctrl+S")
	_tool_button(bar, "다른 이름으로", func(): _open_dialog("save"))
	bar.add_child(VSeparator.new())
	_tool_button(bar, "↶", _undo_action, "실행 취소 (Ctrl+Z)")
	_tool_button(bar, "↷", _redo_action, "다시 실행 (Ctrl+Shift+Z / Ctrl+Y)")
	bar.add_child(VSeparator.new())
	_tool_button(bar, "+ 노드 추가", func(): _show_add_menu(graph_edit.get_screen_position() + graph_edit.size * 0.5, graph_edit.size * 0.5), "그래프 빈 곳 우클릭으로도 추가할 수 있습니다")
	_tool_button(bar, "정렬", _on_arrange, "노드를 자동 정렬합니다")
	_tool_button(bar, "전체 보기", _frame_all, "모든 노드가 보이도록 화면을 맞춥니다")
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title_label)
	_tool_button(bar, "이음새 검사", _on_check_seams, "타일링 용도(띠/타일)일 때 가장자리가 이어지는지 검사하고 원인 노드를 찾습니다")
	var export_btn := _tool_button(bar, "내보내기 (PNG)", _on_export, "스프라이트 시트 PNG 와 게임용 리소스를 만듭니다")
	export_btn.modulate = Color(0.75, 1.0, 0.8)
	_tool_button(bar, "?", _show_help, "사용법")

	# ---- 본문: 그래프 | 오른쪽 패널 ----
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	graph_edit = GraphEdit.new()
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.right_disconnects = true
	graph_edit.show_arrange_button = false
	for a in 3:
		graph_edit.add_valid_left_disconnect_type(a)
		for b in 3:
			graph_edit.add_valid_connection_type(a, b)
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.delete_nodes_request.connect(_on_delete_nodes)
	graph_edit.duplicate_nodes_request.connect(_on_duplicate_nodes)
	graph_edit.popup_request.connect(func(pos: Vector2):
		_pending_link = {}
		_show_add_menu(graph_edit.get_screen_position() + pos, pos))
	graph_edit.connection_to_empty.connect(func(from: StringName, port: int, pos: Vector2):
		_pending_link = {"from": int(String(from)), "port": port}
		_show_add_menu(graph_edit.get_screen_position() + pos, pos))
	graph_edit.connection_from_empty.connect(func(to: StringName, port: int, pos: Vector2):
		_pending_link = {"to": int(String(to)), "port": port}
		_show_add_menu(graph_edit.get_screen_position() + pos, pos))
	graph_edit.node_selected.connect(_on_node_selected)
	graph_edit.node_deselected.connect(_on_node_deselected)
	graph_edit.end_node_move.connect(_sync_positions)
	split.add_child(graph_edit)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(420, 0)
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	# 미리보기 옵션
	var pv_bar := HBoxContainer.new()
	right.add_child(pv_bar)
	preview_mode_opt = OptionButton.new()
	for t in ["프레임", "시트 전체", "2×2 타일"]:
		preview_mode_opt.add_item(t)
	preview_mode_opt.tooltip_text = "미리보기 방식. 2×2 타일은 반복했을 때 이음새를 눈으로 확인할 때 씁니다."
	preview_mode_opt.item_selected.connect(func(_i): _update_preview_size())
	pv_bar.add_child(preview_mode_opt)
	bg_opt = OptionButton.new()
	for t in ["체커", "검정", "흰색"]:
		bg_opt.add_item(t)
	bg_opt.item_selected.connect(func(i): preview.background = i)
	pv_bar.add_child(bg_opt)
	preview_selected_cb = CheckBox.new()
	preview_selected_cb.text = "선택한 노드만 보기"
	preview_selected_cb.toggled.connect(func(_on): _update_preview_target())
	pv_bar.add_child(preview_selected_cb)

	preview = VfxForgePreviewView.new()
	preview.custom_minimum_size = Vector2(400, 400)
	preview.point_dragged.connect(_on_bezier_point_dragged)
	right.add_child(preview)

	# 타임라인
	var tl := HBoxContainer.new()
	right.add_child(tl)
	play_button = Button.new()
	play_button.text = "❚❚"
	play_button.custom_minimum_size.x = 34
	play_button.tooltip_text = "재생/일시정지"
	play_button.pressed.connect(func(): _set_playing(not _playing))
	tl.add_child(play_button)
	timeline = HSlider.new()
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timeline.step = 1
	timeline.value_changed.connect(func(v):
		if not _updating_ui:
			_set_playing(false)
			_set_frame(int(v)))
	tl.add_child(timeline)
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 120
	tl.add_child(frame_label)

	# 베지어 키 포즈 편집
	bezier_box = VBoxContainer.new()
	bezier_box.visible = false
	right.add_child(bezier_box)
	_build_bezier_box()

	# 설정
	right.add_child(_section_label("내보내기 설정"))
	var grid := GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	size_opt = OptionButton.new()
	for s in [256, 512, 1024]:
		size_opt.add_item("%d px" % s, s)
	size_opt.item_selected.connect(func(i): _set_setting("frame_size", size_opt.get_item_id(i)))
	_grid_row(grid, "프레임 크기", size_opt)
	var gh := HBoxContainer.new()
	cols_spin = _spin(1, 16, 1)
	rows_spin = _spin(1, 16, 1)
	cols_spin.value_changed.connect(func(v): _set_setting("cols", int(v)))
	rows_spin.value_changed.connect(func(v): _set_setting("rows", int(v)))
	gh.add_child(cols_spin)
	var x_lab := Label.new()
	x_lab.text = "×"
	gh.add_child(x_lab)
	gh.add_child(rows_spin)
	for n in [1, 2, 3, 4, 8]:
		var b := Button.new()
		b.text = "%d²" % n
		b.tooltip_text = "%d×%d 격자" % [n, n]
		b.pressed.connect(func():
			graph.settings.cols = n
			graph.settings.rows = n
			_settings_changed())
		gh.add_child(b)
	_grid_row(grid, "격자 (가로×세로)", gh)
	loop_cb = CheckBox.new()
	loop_cb.text = "루프 (마지막 → 첫 프레임이 이어짐)"
	loop_cb.toggled.connect(func(on): _set_setting("loop", on))
	_grid_row(grid, "애니메이션", loop_cb)
	usage_opt = OptionButton.new()
	usage_opt.add_item("이펙트 (반복 없음)")
	usage_opt.add_item("띠 Strip (가로 반복, 트레일)")
	usage_opt.add_item("타일 Tile (상하좌우 반복)")
	usage_opt.item_selected.connect(func(i): _set_setting("usage", ["effect", "strip", "tile"][i]))
	_grid_row(grid, "용도", usage_opt)
	import_opt = OptionButton.new()
	import_opt.add_item("2D (무손실, 밉맵 없음)")
	import_opt.add_item("3D (VRAM 압축 + 밉맵)")
	import_opt.item_selected.connect(func(i): _set_setting("import_preset", ["2d", "3d"][i]))
	_grid_row(grid, "임포트", import_opt)
	fps_spin = _spin(1, 120, 1)
	fps_spin.value_changed.connect(func(v): _set_setting("fps", float(v)))
	_grid_row(grid, "FPS", fps_spin)
	blend_opt = OptionButton.new()
	blend_opt.add_item("Add (빛나는 이펙트)")
	blend_opt.add_item("Mix (일반 알파)")
	blend_opt.add_item("Premultiplied")
	blend_opt.item_selected.connect(func(i): _set_setting("blend", ["add", "mix", "premult"][i]))
	_grid_row(grid, "머티리얼 블렌드", blend_opt)
	var ph := HBoxContainer.new()
	path_edit = LineEdit.new()
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.placeholder_text = "res://vfx_textures/이름.png"
	path_edit.text_submitted.connect(func(t): _set_setting("export_path", t))
	path_edit.focus_exited.connect(func(): _set_setting("export_path", path_edit.text))
	ph.add_child(path_edit)
	var pb := Button.new()
	pb.text = "…"
	pb.pressed.connect(func(): _open_dialog("export_path"))
	ph.add_child(pb)
	_grid_row(grid, "PNG 경로", ph)
	frames_cb = CheckBox.new()
	frames_cb.text = "SpriteFrames (AnimatedSprite2D용)"
	frames_cb.toggled.connect(func(on): _set_setting("make_sprite_frames", on))
	_grid_row(grid, "함께 만들기", frames_cb)
	particle_cb = CheckBox.new()
	particle_cb.text = "파티클 머티리얼 (플립북 설정)"
	particle_cb.toggled.connect(func(on): _set_setting("make_particle_material", on))
	_grid_row(grid, "", particle_cb)
	sheet_info = Label.new()
	sheet_info.modulate = Color(1, 1, 1, 0.65)
	right.add_child(sheet_info)

	# 상태 표시줄
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 22
	root.add_child(status_label)

	# 노드 추가 메뉴 (카테고리별 하위 메뉴)
	add_menu = PopupMenu.new()
	add_child(add_menu)
	for cat in Lib.CATEGORIES:
		var sub := PopupMenu.new()
		for t in Lib.types_in_category(cat):
			sub.add_item(Lib.NODES[t].title, _menu_types.size())
			sub.set_item_tooltip(sub.item_count - 1, Lib.NODES[t].get("desc", ""))
			_menu_types.append(t)
		sub.id_pressed.connect(_on_add_menu_id)
		add_menu.add_submenu_node_item(cat, sub)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


func _build_bezier_box() -> void:
	bezier_box.add_child(_section_label("베지어 키 포즈"))
	var hint := Label.new()
	hint.text = "미리보기의 점을 끌어 현재 프레임의 포즈를 만듭니다. 그 프레임에 키가 없으면 자동으로 추가됩니다. 키 사이 프레임은 자동 보간됩니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.7)
	bezier_box.add_child(hint)
	key_list = ItemList.new()
	key_list.custom_minimum_size.y = 90
	key_list.item_selected.connect(_on_key_selected)
	bezier_box.add_child(key_list)
	var hb := HBoxContainer.new()
	bezier_box.add_child(hb)
	var add_b := Button.new()
	add_b.text = "현재 프레임에 키 추가"
	add_b.pressed.connect(func():
		_ensure_key_at_current()
		_after_keys_changed(true))
	hb.add_child(add_b)
	var del_b := Button.new()
	del_b.text = "선택한 키 삭제"
	del_b.pressed.connect(_delete_key)
	hb.add_child(del_b)
	for spec in [["t", "시간", 0.0, 1.0], ["head", "머리 (그려진 끝)", 0.0, 1.0], ["tail", "꼬리 (지워지는 끝)", 0.0, 1.0], ["width", "두께", 0.0, 0.3]]:
		var s := VfxForgeNumberSlider.new().setup(spec[1], spec[2], spec[3], 0.001, 0.0)
		var field: String = spec[0]
		s.value_changed.connect(func(v: float, final: bool): _on_key_field(field, v, final))
		bezier_box.add_child(s)
		key_sliders[field] = s


func _tool_button(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	return l


func _grid_row(grid: GridContainer, label: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


func _spin(lo: float, hi: float, st: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = st
	return s


# ======================================================================
# 그래프 불러오기 / UI 동기화
# ======================================================================

func load_graph(g: VfxForgeGraph, path: String) -> void:
	graph = g
	current_path = path
	_selected_id = -1
	_bezier_node = -1
	_undo.clear()
	_redo.clear()
	_last_snapshot = graph.to_json()
	_rebuild_all()
	_set_dirty(false)
	_frame_all.call_deferred()


## 모든 노드가 보이도록 그래프 화면을 맞춘다
func _frame_all() -> void:
	await get_tree().process_frame
	var rect := Rect2()
	var first := true
	for c in graph_edit.get_children():
		if c is GraphNode:
			var r := Rect2(c.position_offset, c.size)
			rect = r if first else rect.merge(r)
			first = false
	if first or graph_edit.size.x < 10:
		return
	var avail := graph_edit.size - Vector2(60, 60)
	var fit := minf(avail.x / rect.size.x, avail.y / rect.size.y)
	# 너무 작아지면 글자를 읽을 수 없으니 최소 배율을 두고, 그때는 왼쪽 위부터 보여준다
	var z := clampf(fit, 0.5, 1.0)
	graph_edit.zoom = z
	# 줌이 바뀐 뒤 스크롤 범위가 갱신될 때까지 기다린다
	await get_tree().process_frame
	if fit >= z:
		graph_edit.scroll_offset = rect.position * z - (graph_edit.size - rect.size * z) * 0.5
	else:
		graph_edit.scroll_offset = rect.position * z - Vector2(30, 30)


func _rebuild_all() -> void:
	_rebuild_graph_ui()
	_refresh_settings_ui()
	renderer.set_graph(graph, -1)
	_update_preview_target()
	_refresh_timeline()
	_update_bezier_box()


func _rebuild_graph_ui() -> void:
	graph_edit.clear_connections()
	for c in graph_edit.get_children():
		if c is GraphNode:
			graph_edit.remove_child(c)
			c.queue_free()
	var ids := graph.nodes.keys()
	ids.sort()
	for id in ids:
		_add_view(graph.nodes[id])
	_sync_connections()


func _add_view(node: Dictionary) -> VfxForgeNodeView:
	var v := VfxForgeNodeView.new()
	v.setup(node)
	v.param_changed.connect(_on_param_changed)
	v.edit_bezier_requested.connect(func(id):
		graph_edit.set_selected(_view(id))
		_on_node_selected(_view(id)))
	graph_edit.add_child(v)
	return v


func _view(id: int) -> VfxForgeNodeView:
	return graph_edit.get_node_or_null(str(id)) as VfxForgeNodeView


func _sync_connections() -> void:
	graph_edit.clear_connections()
	for id in graph.nodes:
		var v := _view(id)
		if v == null:
			continue
		for p in v._port_rows:
			v.set_port_connected(p, false)
	for c in graph.connections:
		var fv := _view(c.from)
		var tv := _view(c.to)
		if fv == null or tv == null:
			continue
		var fp := fv.out_ports.find(c.from_port)
		var tp := tv.in_ports.find(c.to_port)
		if fp < 0 or tp < 0:
			continue
		graph_edit.connect_node(fv.name, fp, tv.name, tp)
		tv.set_port_connected(c.to_port, true)


func _refresh_settings_ui() -> void:
	_updating_ui = true
	var s := graph.settings
	for i in size_opt.item_count:
		if size_opt.get_item_id(i) == int(s.frame_size):
			size_opt.select(i)
	cols_spin.set_value_no_signal(s.cols)
	rows_spin.set_value_no_signal(s.rows)
	loop_cb.set_pressed_no_signal(s.loop)
	usage_opt.select(["effect", "strip", "tile"].find(s.usage))
	import_opt.select(["2d", "3d"].find(s.import_preset))
	fps_spin.set_value_no_signal(s.fps)
	blend_opt.select(maxi(0, ["add", "mix", "premult"].find(s.blend)))
	path_edit.text = s.export_path
	frames_cb.set_pressed_no_signal(s.make_sprite_frames)
	particle_cb.set_pressed_no_signal(s.make_particle_material)
	var fs := int(s.frame_size)
	sheet_info.text = "시트: %d × %d px · %d 프레임 · %s" % [fs * int(s.cols), fs * int(s.rows), graph.frame_count(), "루프" if s.loop else "1회 재생"]
	_updating_ui = false


func _set_setting(key: String, value) -> void:
	if _updating_ui or graph.settings.get(key) == value:
		return
	graph.settings[key] = value
	_settings_changed()


func _settings_changed() -> void:
	_refresh_settings_ui()
	_refresh_timeline()
	_commit()


func _refresh_timeline() -> void:
	_updating_ui = true
	timeline.max_value = maxi(graph.frame_count() - 1, 0)
	_frame = clampi(_frame, 0, graph.frame_count() - 1)
	timeline.value = _frame
	_updating_ui = false
	_update_preview_size()
	_update_frame_label()


func _set_dirty(d: bool) -> void:
	dirty = d
	var n := current_path.get_file() if current_path != "" else (graph.name + " (저장 안 됨)")
	title_label.text = n + (" *" if dirty else "")


func _status(text: String, error := false) -> void:
	status_label.text = text
	status_label.modulate = Color(1, 0.55, 0.5) if error else Color(1, 1, 1, 0.8)


# ======================================================================
# 미리보기 / 재생
# ======================================================================

func _process(delta: float) -> void:
	if not is_visible_in_tree() or graph == null or _busy:
		return
	if _playing:
		_play_time += delta
		var f := int(_play_time * float(graph.settings.fps)) % maxi(graph.frame_count(), 1)
		if f != _frame:
			_set_frame(f)
	var mode := preview_mode_opt.selected
	var fs := int(graph.settings.frame_size)
	var t := graph.frame_time(_frame)
	if mode == 1:
		var sheet := Vector2(fs * int(graph.settings.cols), fs * int(graph.settings.rows))
		var k := minf(1.0, PREVIEW_MAX / maxf(sheet.x, sheet.y))
		renderer.set_globals(t, true, Vector2i(sheet * k))
	else:
		var ps := mini(fs, 512)
		renderer.set_globals(t, false, Vector2i(ps, ps), 2.0 if mode == 2 else 1.0)


func _update_preview_size() -> void:
	if preview_mode_opt == null or graph == null:
		return
	preview.grid = Vector2i(int(graph.settings.cols), int(graph.settings.rows)) if preview_mode_opt.selected == 1 else (Vector2i(2, 2) if preview_mode_opt.selected == 2 else Vector2i.ONE)
	_update_bezier_overlay()


func _set_playing(p: bool) -> void:
	_playing = p
	play_button.text = "❚❚" if p else "▶"
	if p:
		_play_time = float(_frame) / maxf(float(graph.settings.fps), 1.0)


func _set_frame(f: int) -> void:
	_frame = clampi(f, 0, maxi(graph.frame_count() - 1, 0))
	_updating_ui = true
	timeline.value = _frame
	_updating_ui = false
	_update_frame_label()
	_update_bezier_overlay()


func _update_frame_label() -> void:
	frame_label.text = "%d / %d  (t=%.3f)" % [_frame + 1, graph.frame_count(), graph.frame_time(_frame)]


func _update_preview_target() -> void:
	var target := _selected_id if preview_selected_cb.button_pressed and graph.nodes.has(_selected_id) else -1
	if renderer.target_id != target or renderer.graph != graph:
		renderer.set_graph(graph, target)


# ======================================================================
# 그래프 편집
# ======================================================================

func _show_add_menu(screen_pos: Vector2, graph_local: Vector2) -> void:
	_add_graph_pos = (graph_local + graph_edit.scroll_offset) / graph_edit.zoom
	add_menu.popup(Rect2i(Vector2i(screen_pos), Vector2i.ZERO))


func _on_add_menu_id(id: int) -> void:
	var type: String = _menu_types[id]
	if type == "output" and graph.output_node() >= 0:
		_status("출력 노드는 하나만 둘 수 있습니다.", true)
		return
	var nid := graph.add_node(type, _add_graph_pos)
	var v := _add_view(graph.nodes[nid])
	var def := Lib.get_def(type)
	if _pending_link.has("from"):
		var fv := _view(_pending_link.from)
		var out_name: String = fv.out_ports[_pending_link.port]
		var out_type: int = Lib.get_def(fv.type).outputs[_pending_link.port].type
		var target := ""
		for name in v.in_ports:
			if Lib.input_type(def, name) == out_type:
				target = name
				break
		if target == "" and not v.in_ports.is_empty():
			target = v.in_ports[0]
		if target != "":
			graph.connect_ports(_pending_link.from, out_name, nid, target)
	elif _pending_link.has("to") and not v.out_ports.is_empty():
		var tv := _view(_pending_link.to)
		graph.connect_ports(nid, v.out_ports[0], _pending_link.to, tv.in_ports[_pending_link.port])
	_pending_link = {}
	_sync_connections()
	_structure_changed()


func _on_connection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var fv := _view(int(String(from)))
	var tv := _view(int(String(to)))
	if fv == null or tv == null:
		return
	if not graph.connect_ports(fv.node_id, fv.out_ports[from_port], tv.node_id, tv.in_ports[to_port]):
		_status("순환 연결은 만들 수 없습니다.", true)
		return
	_sync_connections()
	_structure_changed()


func _on_disconnection_request(_from: StringName, _from_port: int, to: StringName, to_port: int) -> void:
	var tv := _view(int(String(to)))
	if tv == null:
		return
	graph.disconnect_input(tv.node_id, tv.in_ports[to_port])
	_sync_connections()
	_structure_changed()


func _on_delete_nodes(names: Array) -> void:
	for n in names:
		var id := int(String(n))
		if not graph.nodes.has(id):
			continue
		if graph.nodes[id].type == "output":
			_status("출력 노드는 지울 수 없습니다.", true)
			continue
		graph.remove_node(id)
		var v := _view(id)
		if v:
			graph_edit.remove_child(v)
			v.queue_free()
		if _selected_id == id:
			_selected_id = -1
	_sync_connections()
	_update_bezier_box()
	_structure_changed()


func _on_duplicate_nodes() -> void:
	var map := {}
	for c in graph_edit.get_children():
		if c is VfxForgeNodeView and c.selected and c.type != "output":
			var src: Dictionary = graph.nodes[c.node_id]
			var nid := graph.add_node(src.type, src.pos + Vector2(40, 40))
			for k in src.params:
				graph.nodes[nid].params[k] = _deep_copy(src.params[k])
			map[c.node_id] = nid
	# 복제한 노드끼리의 연결은 그대로 복제
	for c in graph.connections.duplicate():
		if map.has(c.from) and map.has(c.to):
			graph.connect_ports(map[c.from], c.from_port, map[c.to], c.to_port)
	for old in map:
		_view(old).selected = false
		var v := _add_view(graph.nodes[map[old]])
		v.selected = true
	_sync_connections()
	_structure_changed()


static func _deep_copy(v):
	if v is Array:
		var out := []
		for x in v:
			out.append(_deep_copy(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _deep_copy(v[k])
		return out
	return v


func _on_arrange() -> void:
	graph_edit.arrange_nodes()
	_sync_positions()


func _sync_positions() -> void:
	for c in graph_edit.get_children():
		if c is VfxForgeNodeView and graph.nodes.has(c.node_id):
			graph.nodes[c.node_id].pos = c.position_offset
	_commit()


func _on_node_selected(n: Node) -> void:
	if n is VfxForgeNodeView:
		_selected_id = n.node_id
		_update_bezier_box()
		_update_preview_target()


func _on_node_deselected(n: Node) -> void:
	if n is VfxForgeNodeView and n.node_id == _selected_id:
		_selected_id = -1
		_update_bezier_box()
		_update_preview_target()


func _on_param_changed(id: int, param: String, value, final: bool) -> void:
	if not graph.nodes.has(id):
		return
	graph.nodes[id].params[param] = value
	renderer.update_param(id, param)
	if final:
		_commit()
	else:
		_set_dirty(true)


func _structure_changed() -> void:
	_update_preview_target()
	renderer.recompile()
	_commit()


# ======================================================================
# 베지어 키 포즈
# ======================================================================

func _update_bezier_box() -> void:
	var id := _selected_id
	_bezier_node = id if graph.nodes.has(id) and graph.nodes[id].type == "bezier" else -1
	bezier_box.visible = _bezier_node >= 0
	if _bezier_node < 0:
		preview.bezier_points = []
		return
	var keys: Array = _keys()
	key_list.clear()
	for i in keys.size():
		var k: Dictionary = keys[i]
		key_list.add_item("t=%.3f   머리 %.2f · 꼬리 %.2f · 두께 %.3f" % [k.t, k.head, k.tail, k.width])
	_bezier_key = clampi(_bezier_key, -1, keys.size() - 1)
	if _bezier_key >= 0:
		key_list.select(_bezier_key)
	_refresh_key_sliders()
	_update_bezier_overlay()


func _keys() -> Array:
	return graph.nodes[_bezier_node].params["poses"] if _bezier_node >= 0 else []


func _refresh_key_sliders() -> void:
	var keys := _keys()
	var has := _bezier_key >= 0 and _bezier_key < keys.size()
	for f in key_sliders:
		key_sliders[f].visible = has
		if has:
			key_sliders[f].set_value_no_signal(keys[_bezier_key][f])


func _current_key_index() -> int:
	var t := graph.frame_time(_frame)
	var keys := _keys()
	for i in keys.size():
		if absf(keys[i].t - t) < 0.0005:
			return i
	return -1


## 셰이더와 같은 규칙으로 시간 t 의 포즈를 계산
func _pose_at(keys: Array, t: float, smooth: bool) -> Dictionary:
	if keys.is_empty():
		return {}
	var k := 0
	for i in range(keys.size() - 1):
		if t >= keys[i + 1].t:
			k = i + 1
	var k2 := mini(k + 1, keys.size() - 1)
	var f := 0.0
	if k2 != k:
		f = clampf((t - keys[k].t) / maxf(keys[k2].t - keys[k].t, 1e-5), 0.0, 1.0)
	if smooth:
		f = f * f * (3.0 - 2.0 * f)
	var a: Dictionary = keys[k]
	var b: Dictionary = keys[k2]
	var pts: Array[Vector2] = []
	for j in 4:
		pts.append(a.p[j].lerp(b.p[j], f))
	return {"t": t, "p": pts, "head": lerpf(a.head, b.head, f), "tail": lerpf(a.tail, b.tail, f), "width": lerpf(a.width, b.width, f)}


func _update_bezier_overlay() -> void:
	if _bezier_node < 0 or preview_mode_opt.selected != 0:
		preview.bezier_points = []
		return
	var keys := _keys()
	var pose := _pose_at(keys, graph.frame_time(_frame), graph.nodes[_bezier_node].params.smooth)
	preview.bezier_points = pose.get("p", [])
	var ki := _current_key_index()
	preview.bezier_on_key = ki >= 0
	if ki >= 0 and ki != _bezier_key:
		_bezier_key = ki
		key_list.select(ki)
		_refresh_key_sliders()


func _ensure_key_at_current() -> int:
	var ki := _current_key_index()
	if ki >= 0:
		return ki
	var keys := _keys()
	if keys.size() >= Lib.MAX_BEZIER_KEYS:
		_status("키는 최대 %d개까지 만들 수 있습니다." % Lib.MAX_BEZIER_KEYS, true)
		return -1
	var t := graph.frame_time(_frame)
	var pose := _pose_at(keys, t, graph.nodes[_bezier_node].params.smooth)
	keys.append(pose)
	keys.sort_custom(func(a, b): return a.t < b.t)
	_bezier_key = keys.find(pose)
	return _bezier_key


func _on_bezier_point_dragged(index: int, uv: Vector2, final: bool) -> void:
	if _bezier_node < 0:
		return
	var ki := _ensure_key_at_current()
	if ki < 0:
		return
	_keys()[ki].p[index] = uv
	_after_keys_changed(final)


func _after_keys_changed(final: bool) -> void:
	renderer.update_param(_bezier_node, "poses")
	_view(_bezier_node).refresh_param("poses", _keys())
	if final:
		_update_bezier_box()
		_commit()
	else:
		_update_bezier_overlay()
		_set_dirty(true)


func _on_key_selected(i: int) -> void:
	_bezier_key = i
	_refresh_key_sliders()
	var t: float = _keys()[i].t
	var n := graph.frame_count()
	var f := roundi(t * (n if graph.settings.loop else n - 1))
	_set_playing(false)
	_set_frame(f)


func _on_key_field(field: String, v: float, final: bool) -> void:
	var keys := _keys()
	if _bezier_key < 0 or _bezier_key >= keys.size():
		return
	keys[_bezier_key][field] = v
	if field == "t" and final:
		var k = keys[_bezier_key]
		keys.sort_custom(func(a, b): return a.t < b.t)
		_bezier_key = keys.find(k)
	_after_keys_changed(final)


func _delete_key() -> void:
	var keys := _keys()
	if _bezier_key < 0 or keys.size() <= 1:
		_status("키는 최소 1개가 있어야 합니다.", true)
		return
	keys.remove_at(_bezier_key)
	_bezier_key = -1
	_after_keys_changed(true)


# ======================================================================
# 실행 취소
# ======================================================================

func _commit() -> void:
	var cur := graph.to_json()
	if cur == _last_snapshot:
		return
	_undo.append(_last_snapshot)
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()
	_last_snapshot = cur
	_set_dirty(true)


func _undo_action() -> void:
	if _undo.is_empty():
		return
	_redo.append(_last_snapshot)
	_last_snapshot = _undo.pop_back()
	_restore(_last_snapshot)


func _redo_action() -> void:
	if _redo.is_empty():
		return
	_undo.append(_last_snapshot)
	_last_snapshot = _redo.pop_back()
	_restore(_last_snapshot)


func _restore(json: String) -> void:
	var sel := _selected_id
	graph = VfxForgeGraph.from_dict(JSON.parse_string(json))
	_selected_id = sel if graph.nodes.has(sel) else -1
	_rebuild_all()
	if _selected_id >= 0:
		graph_edit.set_selected(_view(_selected_id))
	_set_dirty(true)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not get_global_rect().has_point(get_global_mouse_position()):
		return
	# 글자 입력 중에는 단축키를 가로채지 않는다
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	if ctrl and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo_action()
		else:
			_undo_action()
		get_viewport().set_input_as_handled()
	elif ctrl and event.keycode == KEY_Y:
		_redo_action()
		get_viewport().set_input_as_handled()
	elif ctrl and event.keycode == KEY_S:
		_on_save()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE and not ctrl and not (focus is Button):
		_set_playing(not _playing)
		get_viewport().set_input_as_handled()


# ======================================================================
# 파일
# ======================================================================

func _on_new() -> void:
	load_graph(VfxForgeGraph.create_default(), "")
	_status("새 레시피를 만들었습니다.")


func open_recipe(path: String) -> bool:
	var g := VfxForgeGraph.load_file(path)
	if g == null:
		_status("레시피를 열지 못했습니다: " + path, true)
		return false
	# 예제 레시피는 원본을 덮어쓰지 않도록 '저장'할 때 새 경로를 묻는다
	load_graph(g, "" if path.begins_with(RECIPE_DIR) else path)
	_status("열었습니다: " + path)
	return true


## 내보낸 PNG 를 만든 레시피를 찾아서 연다
func open_for_texture(png_path: String) -> bool:
	for p in find_recipes("res://"):
		var g := VfxForgeGraph.load_file(p)
		if g and g.settings.export_path == png_path:
			return open_recipe(p)
	_status("이 텍스처를 만든 레시피를 찾지 못했습니다: " + png_path, true)
	return false


static func find_recipes(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".vfx.json"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(find_recipes(dir.path_join(sub)))
	return out


func _fill_recipe_menu() -> void:
	var pm := recipe_menu.get_popup()
	pm.clear()
	var files := []
	for f in DirAccess.get_files_at(RECIPE_DIR):
		if f.ends_with(".vfx.json"):
			files.append(f)
	files.sort()
	for i in files.size():
		var g := VfxForgeGraph.load_file(RECIPE_DIR.path_join(files[i]))
		pm.add_item(g.name if g else files[i], i)
		pm.set_item_metadata(i, RECIPE_DIR.path_join(files[i]))


func _on_recipe_menu(id: int) -> void:
	var pm := recipe_menu.get_popup()
	open_recipe(pm.get_item_metadata(pm.get_item_index(id)))


func _open_dialog(mode: String) -> void:
	_file_mode = mode
	file_dialog.clear_filters()
	match mode:
		"open":
			file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			file_dialog.add_filter("*.vfx.json", "VFX Forge 레시피")
			file_dialog.current_dir = USER_RECIPE_DIR if DirAccess.dir_exists_absolute(USER_RECIPE_DIR) else RECIPE_DIR
			file_dialog.title = "레시피 열기"
		"save":
			file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			file_dialog.add_filter("*.vfx.json", "VFX Forge 레시피")
			DirAccess.make_dir_recursive_absolute(USER_RECIPE_DIR)
			file_dialog.current_dir = USER_RECIPE_DIR
			file_dialog.current_file = graph.name.to_snake_case() + ".vfx.json"
			file_dialog.title = "레시피 저장"
		"export_path", "export":
			file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			file_dialog.add_filter("*.png", "PNG")
			var p: String = graph.settings.export_path
			file_dialog.current_dir = p.get_base_dir() if p != "" else "res://"
			file_dialog.current_file = p.get_file() if p != "" else graph.name.to_snake_case() + ".png"
			file_dialog.title = "내보낼 PNG 경로"
	file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	match _file_mode:
		"open":
			open_recipe(path)
		"save":
			if not path.ends_with(".vfx.json"):
				path = path.trim_suffix(".json") + ".vfx.json"
			_save_to(path)
		"export_path":
			_set_setting("export_path", path)
		"export":
			_set_setting("export_path", path)
			_on_export()


func _on_save() -> void:
	if current_path == "":
		_open_dialog("save")
	else:
		_save_to(current_path)


func _save_to(path: String) -> void:
	if current_path == "" or graph.name == "Untitled":
		graph.name = path.get_file().trim_suffix(".vfx.json")
	var err := graph.save(path)
	if err != OK:
		_status("저장 실패: %s (%s)" % [path, error_string(err)], true)
		return
	current_path = path
	_set_dirty(false)
	_status("저장했습니다: " + path)
	exported.emit({"ok": true, "files": [path], "recipe_only": true})


# ======================================================================
# 내보내기 / 이음새 검사
# ======================================================================

func _on_export() -> void:
	if _busy:
		return
	if str(graph.settings.export_path) == "":
		_open_dialog("export")
		return
	_busy = true
	_status("내보내는 중...")
	var res: Dictionary = await VfxForgeExporter.export_graph(renderer, graph)
	_busy = false
	if not res.ok:
		_status(res.error, true)
		return
	if current_path != "":
		graph.save(current_path)
		_set_dirty(false)
	var extra := "" if current_path != "" else "  (레시피는 아직 저장되지 않았습니다. 나중에 다시 고치려면 저장하세요.)"
	_status("내보냈습니다: %s (%d×%d, %d프레임)%s" % [", ".join(res.files), res.size.x, res.size.y, graph.frame_count(), extra])
	exported.emit(res)


func _on_check_seams() -> void:
	if _busy:
		return
	_busy = true
	_status("이음새 검사 중...")
	var res: Dictionary = await VfxForgeExporter.check_seams(renderer, graph)
	_busy = false
	_status(res.message, not res.ok)
	if res.node >= 0 and _view(res.node):
		for c in graph_edit.get_children():
			if c is GraphNode:
				c.selected = false
		graph_edit.set_selected(_view(res.node))


func _show_help() -> void:
	var d := AcceptDialog.new()
	d.title = "VFX Forge 사용법"
	d.dialog_text = """노드를 연결해 스타일라이즈드 VFX 텍스처/스프라이트 시트를 만듭니다.

· 노드 추가: 그래프 빈 곳 우클릭, 또는 포트를 빈 곳으로 끌어 놓기
· 연결 끊기: 입력 포트를 끌어서 빈 곳에 놓기 · 노드 삭제: Delete · 복제: Ctrl+D
· 숫자 칸: 좌우 드래그로 변경 (Shift = 미세), 클릭하면 직접 입력 (수식 가능)
· 보라 포트 = 좌표(UV), 회색 = 흑백 값, 주황 = 색
· 파라미터 왼쪽에 포트가 있으면 다른 노드(시간, 타이밍 등)를 꽂아 애니메이션할 수 있습니다
· 스페이스: 재생/정지 · Ctrl+Z / Ctrl+Shift+Z: 실행 취소/다시 실행 · Ctrl+S: 저장

애니메이션: 시간 노드의 t 는 첫 프레임 0 → 마지막 프레임 1 입니다.
루프를 켜면 마지막 프레임 다음이 첫 프레임과 이어지도록 흐름/노이즈 변화 값이 정수로 맞춰집니다.

용도: 띠(Strip)/타일(Tile)을 고르면 노이즈와 도형이 가장자리에서 자동으로 이어집니다.
'이음새 검사'로 확인하고, 이음새가 있으면 원인 노드를 선택해 줍니다.

내보내기: 시트 PNG + 임포트 설정 + SpriteFrames(.tres) + 파티클 머티리얼(.tres)을 만듭니다.
· AnimatedSprite2D 에 _frames.tres 를 넣으면 바로 재생됩니다.
· GPUParticles2D 의 Material 에 _particle.tres 를 넣고, ParticleProcessMaterial 의 Animation > Speed 를 1 로 두면 수명 동안 시트를 한 번 재생합니다."""
	add_child(d)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.popup_centered()
