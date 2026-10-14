## Card Burn 데모: 카드 셰이더 + 오른쪽 파라미터 패널.
## 패널은 셰이더 uniform 목록을 읽어서 자동으로 만든다. 셰이더에 uniform 을 추가하면 슬라이더도 자동으로 생긴다.
## 에디터에서는 Card 노드를 선택하고 인스펙터 Material > Shader Parameters 에서 같은 값을 조절할 수 있다.
extends Node2D

@export var auto_play := true
@export var cycle_seconds := 4.0

var _mat: ShaderMaterial
var _t := 0.0
var _progress_slider: HSlider
var _progress_label: Label
var _defaults := {}

@onready var _card: Sprite2D = $Card
@onready var _list: VBoxContainer = $UI/Panel/Margin/Scroll/List


func _ready() -> void:
	_mat = _card.material as ShaderMaterial
	_build_header()
	for u in _mat.shader.get_shader_uniform_list(true):
		if u.usage & PROPERTY_USAGE_GROUP:
			_add_group_label(u.name)
			continue
		_defaults[u.name] = _get_param(u.name)
		_add_param_row(u)


func _process(delta: float) -> void:
	if not auto_play:
		return
	# 0 → 1 로 태우고, 끝에서 잠깐 멈췄다가 다시 처음부터
	_t = fmod(_t + delta, cycle_seconds + 0.8)
	var v := clampf(_t / cycle_seconds, 0.0, 1.0)
	_mat.set_shader_parameter("burn_progress", v)
	_progress_slider.set_value_no_signal(v)
	_progress_label.text = _fmt(v)


func _get_param(param: String) -> Variant:
	var v: Variant = _mat.get_shader_parameter(param)
	if v == null:  # 머티리얼에 저장 안 된 값은 셰이더 기본값
		v = RenderingServer.shader_get_parameter_default(_mat.shader.get_rid(), param)
	return v


func _build_header() -> void:
	var title := Label.new()
	title.text = "Card Burn — Shader Parameters"
	title.add_theme_font_size_override("font_size", 18)
	_list.add_child(title)

	var row := HBoxContainer.new()
	var play := CheckBox.new()
	play.text = "자동 재생"
	play.button_pressed = auto_play
	play.toggled.connect(func(on: bool) -> void: auto_play = on)
	row.add_child(play)
	var reset := Button.new()
	reset.text = "기본값으로"
	reset.pressed.connect(_reset_all)
	row.add_child(reset)
	_list.add_child(row)

	var hint := Label.new()
	hint.text = "Burn Progress 슬라이더를 잡으면 자동 재생이 멈춥니다."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	_list.add_child(hint)
	_list.set_meta("play_toggle", play)


func _add_group_label(group: String) -> void:
	var l := Label.new()
	l.text = group.capitalize()
	l.add_theme_color_override("font_color", Color(0.55, 0.87, 1.0))
	_list.add_child(HSeparator.new())
	_list.add_child(l)


func _add_param_row(u: Dictionary) -> void:
	var param: String = u.name
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = param.capitalize()
	name_label.custom_minimum_size.x = 140
	row.add_child(name_label)

	match u.type:
		TYPE_FLOAT:
			var range_parts: PackedStringArray = String(u.hint_string).split(",")
			var slider := HSlider.new()
			slider.min_value = float(range_parts[0]) if range_parts.size() > 1 else 0.0
			slider.max_value = float(range_parts[1]) if range_parts.size() > 1 else 1.0
			slider.step = float(range_parts[2]) if range_parts.size() > 2 else 0.001
			slider.value = _get_param(param)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.custom_minimum_size.x = 150
			var value_label := Label.new()
			value_label.custom_minimum_size.x = 52
			value_label.text = _fmt(slider.value)
			slider.value_changed.connect(func(v: float) -> void:
				_mat.set_shader_parameter(param, v)
				value_label.text = _fmt(v)
				# 사용자가 진행도 슬라이더를 직접 잡으면 자동 재생을 끈다
				if param == "burn_progress" and slider.has_focus():
					(_list.get_meta("play_toggle") as CheckBox).button_pressed = false)
			if param == "burn_progress":
				_progress_slider = slider
				_progress_label = value_label
			row.add_child(slider)
			row.add_child(value_label)
			row.set_meta("reset", func() -> void: slider.value = _defaults[param])
		TYPE_COLOR:
			var picker := ColorPickerButton.new()
			picker.color = _get_param(param)
			picker.custom_minimum_size = Vector2(150, 24)
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			picker.color_changed.connect(func(c: Color) -> void: _mat.set_shader_parameter(param, c))
			row.add_child(picker)
			row.set_meta("reset", func() -> void:
				picker.color = _defaults[param]
				_mat.set_shader_parameter(param, _defaults[param]))
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = _get_param(param)
			check.toggled.connect(func(on: bool) -> void: _mat.set_shader_parameter(param, on))
			row.add_child(check)
			row.set_meta("reset", func() -> void: check.button_pressed = _defaults[param])
		_:
			return
	_list.add_child(row)


func _reset_all() -> void:
	for row in _list.get_children():
		if row.has_meta("reset"):
			(row.get_meta("reset") as Callable).call()


func _fmt(v: float) -> String:
	return ("%.3f" % v) if absf(v) < 10.0 else ("%.1f" % v)
