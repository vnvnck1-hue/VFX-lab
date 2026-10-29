## 그래프 에디터에 놓이는 노드 하나. 노드 정의(node_library)를 읽어 포트와 파라미터 컨트롤을 만든다.
@tool
class_name VfxForgeNodeView
extends GraphNode

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")

signal param_changed(node_id: int, param: String, value: Variant, final: bool)
signal edit_bezier_requested(node_id: int)

var node_id := -1
var type := ""
var def := {}
## 포트 번호 → 입력/파라미터 이름, 출력 이름
var in_ports: Array[String] = []
var out_ports: Array[String] = []
## 포트로 연결 가능한 파라미터: 이름 → [컨트롤, 연결됐을 때 보이는 라벨]
var _port_rows := {}
var _controls := {}


func setup(node: Dictionary) -> void:
	node_id = node.id
	type = node.type
	def = Lib.get_def(type)
	name = str(node_id)
	title = def.title
	position_offset = node.pos
	tooltip_text = def.get("desc", "")
	custom_minimum_size = Vector2(200, 0)
	var slot := 0
	for o in def.outputs:
		var l := Label.new()
		l.text = o.name
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(l)
		set_slot(slot, false, 0, Color.WHITE, true, o.type, Lib.PORT_COLORS[o.type])
		out_ports.append(o.name)
		slot += 1
	for inp in def.inputs:
		var l := Label.new()
		l.text = inp.name
		add_child(l)
		set_slot(slot, true, inp.type, Lib.PORT_COLORS[inp.type], false, 0, Color.WHITE)
		in_ports.append(inp.name)
		slot += 1
	for p in def.params:
		var row := _make_row(p, node.params[p.name])
		add_child(row)
		if p.get("port", false):
			var pt := Lib.COLOR if p.type == "color" else Lib.FLOAT
			set_slot(slot, true, pt, Lib.PORT_COLORS[pt], false, 0, Color.WHITE)
			in_ports.append(p.name)
		slot += 1
	if type == "output":
		self_modulate = Color(1.0, 0.85, 0.6)


func _make_row(p: Dictionary, v) -> Control:
	var ctrl: Control
	match p.type:
		"float", "int":
			var s := VfxForgeNumberSlider.new().setup(p.label, p.get("min", 0.0), p.get("max", 1.0), p.get("step", 1.0 if p.type == "int" else 0.001), float(v))
			s.value_changed.connect(func(val: float, final: bool):
				param_changed.emit(node_id, p.name, int(val) if p.type == "int" else val, final))
			ctrl = s
		"vec2":
			var h := HBoxContainer.new()
			var lab := Label.new()
			lab.text = p.label
			lab.custom_minimum_size.x = 46
			h.add_child(lab)
			var sx := VfxForgeNumberSlider.new().setup("x", p.get("min", 0.0), p.get("max", 1.0), 0.001, v.x)
			var sy := VfxForgeNumberSlider.new().setup("y", p.get("min", 0.0), p.get("max", 1.0), 0.001, v.y)
			sx.custom_minimum_size.x = 70
			sy.custom_minimum_size.x = 70
			h.add_child(sx)
			h.add_child(sy)
			sx.value_changed.connect(func(val: float, final: bool): param_changed.emit(node_id, p.name, Vector2(val, sy.value), final))
			sy.value_changed.connect(func(val: float, final: bool): param_changed.emit(node_id, p.name, Vector2(sx.value, val), final))
			ctrl = h
			_controls[p.name + ".x"] = sx
			_controls[p.name + ".y"] = sy
		"enum":
			var h := HBoxContainer.new()
			var lab := Label.new()
			lab.text = p.label
			h.add_child(lab)
			var ob := OptionButton.new()
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.fit_to_longest_item = false
			for o in p.options:
				ob.add_item(o)
			ob.selected = int(v)
			ob.item_selected.connect(func(i: int): param_changed.emit(node_id, p.name, i, true))
			h.add_child(ob)
			ctrl = h
			_controls[p.name] = ob
		"bool":
			var cb := CheckBox.new()
			cb.text = p.label
			cb.button_pressed = bool(v)
			cb.toggled.connect(func(on: bool): param_changed.emit(node_id, p.name, on, true))
			ctrl = cb
		"color":
			var h := HBoxContainer.new()
			var lab := Label.new()
			lab.text = p.label
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(lab)
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(70, 22)
			cp.color = v
			cp.edit_alpha = true
			cp.color_changed.connect(func(c: Color): param_changed.emit(node_id, p.name, c, false))
			cp.popup_closed.connect(func(): param_changed.emit(node_id, p.name, cp.color, true))
			h.add_child(cp)
			ctrl = h
			_controls[p.name] = cp
		"gradient":
			var ge := VfxForgeGradientEdit.new()
			ge.set_stops(v)
			ge.changed.connect(func(stops: Array, final: bool): param_changed.emit(node_id, p.name, stops.duplicate(true), final))
			ctrl = ge
		"bezier":
			var b := Button.new()
			b.text = "키 포즈 편집 (%d개)" % v.size()
			b.pressed.connect(func(): edit_bezier_requested.emit(node_id))
			ctrl = b
		_:
			ctrl = Label.new()
	if not _controls.has(p.name):
		_controls[p.name] = ctrl
	if p.get("port", false):
		# 다른 노드가 연결되면 컨트롤을 숨기고 이름만 보여준다
		var box := VBoxContainer.new()
		var lab := Label.new()
		lab.text = "← " + p.label
		lab.visible = false
		lab.modulate = Color(1, 1, 1, 0.7)
		box.add_child(ctrl)
		box.add_child(lab)
		_port_rows[p.name] = [ctrl, lab]
		return box
	return ctrl


func set_port_connected(param: String, connected: bool) -> void:
	if _port_rows.has(param):
		_port_rows[param][0].visible = not connected
		_port_rows[param][1].visible = connected


## 외부(키 포즈 편집 등)에서 바뀐 값을 컨트롤에 반영
func refresh_param(param: String, v) -> void:
	var p := Lib.find_param(def, param)
	if p.is_empty():
		return
	match p.type:
		"float", "int":
			_controls[param].set_value_no_signal(float(v))
		"vec2":
			_controls[param + ".x"].set_value_no_signal(v.x)
			_controls[param + ".y"].set_value_no_signal(v.y)
		"bezier":
			_controls[param].text = "키 포즈 편집 (%d개)" % v.size()
		"gradient":
			_controls[param].set_stops(v)
