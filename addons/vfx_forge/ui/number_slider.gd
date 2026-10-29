## 드래그로 값을 바꾸는 숫자 칸. 클릭하면 직접 입력, Shift 를 누르고 드래그하면 미세 조정.
## 에디터 전용 클래스(EditorSpinSlider)를 쓰지 않아서 단독 실행 앱에서도 동작한다.
@tool
class_name VfxForgeNumberSlider
extends Control

signal value_changed(value: float, final: bool)

var min_value := 0.0
var max_value := 1.0
var step := 0.001
var value := 0.0
var label := ""

var _dragging := false
var _press_x := 0.0
var _press_value := 0.0
var _edit: LineEdit


func _init() -> void:
	custom_minimum_size = Vector2(150, 22)
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(p_label: String, p_min: float, p_max: float, p_step: float, p_value: float) -> VfxForgeNumberSlider:
	label = p_label
	min_value = p_min
	max_value = p_max
	step = p_step
	value = p_value
	tooltip_text = "%s\n드래그: 값 변경 (Shift = 미세 조정) · 클릭: 직접 입력" % p_label
	return self


func set_value_no_signal(v: float) -> void:
	value = v
	queue_redraw()


func _fmt(v: float) -> String:
	if step >= 1.0:
		return str(roundi(v))
	var decimals := clampi(int(ceil(-log(step) / log(10.0))), 1, 4)
	return String.num(v, decimals)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.32))
	var f := clampf(inverse_lerp(min_value, max_value, value), 0.0, 1.0) if max_value > min_value else 0.0
	draw_rect(Rect2(0, 0, size.x * f, size.y), Color(0.33, 0.52, 0.86, 0.6))
	draw_rect(r, Color(1, 1, 1, 0.08), false)
	var font := get_theme_default_font()
	var fs := 13
	var y := (size.y + fs * 0.72) * 0.5
	draw_string(font, Vector2(6, y), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, fs, Color(1, 1, 1, 0.72))
	draw_string(font, Vector2(0, y), _fmt(value), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, fs, Color(1, 1, 1, 0.98))


func _set_from_user(v: float, final: bool) -> void:
	if step > 0.0:
		v = snappedf(v, step)
	value = v
	queue_redraw()
	value_changed.emit(value, final)


func _gui_input(event: InputEvent) -> void:
	if _edit:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_x = event.position.x
			_press_value = value
			_dragging = false
		else:
			if _dragging:
				_dragging = false
				value_changed.emit(value, true)
			else:
				_open_edit()
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var dx: float = event.position.x - _press_x
		if not _dragging and absf(dx) > 3.0:
			_dragging = true
		if _dragging:
			var sens := (max_value - min_value) / maxf(size.x, 1.0)
			if event.shift_pressed:
				sens *= 0.1
			_set_from_user(clampf(_press_value + dx * sens, min_value, max_value), false)
		accept_event()


func _open_edit() -> void:
	_edit = LineEdit.new()
	_edit.text = _fmt(value)
	_edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_edit)
	_edit.grab_focus()
	_edit.select_all()
	_edit.text_submitted.connect(func(_t): _close_edit(true))
	_edit.focus_exited.connect(func(): _close_edit(true))


func _close_edit(apply: bool) -> void:
	if _edit == null:
		return
	var e := _edit
	_edit = null
	if apply:
		var expr := Expression.new()
		if expr.parse(e.text) == OK:
			var v = expr.execute()
			if v is float or v is int:
				_set_from_user(float(v), true)
	e.queue_free()
