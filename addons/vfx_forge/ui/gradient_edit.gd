## 그라데이션 색 띠 편집기.
## 빈 곳 클릭: 색 칸 추가 · 칸 드래그: 위치 이동 · 칸 더블클릭: 색 고르기 · 칸 우클릭: 삭제
@tool
class_name VfxForgeGradientEdit
extends Control

signal changed(stops: Array, final: bool)

const BAR_H := 18.0
const MARK_H := 10.0

## [[offset, Color], ...] (offset 순으로 정렬)
var stops: Array = []

var _sel := -1
var _dragging := false
var _popup: PopupPanel
var _picker: ColorPicker


func _init() -> void:
	custom_minimum_size = Vector2(190, BAR_H + MARK_H + 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "빈 곳 클릭: 색 추가 · 드래그: 이동 · 더블클릭: 색 고르기 · 우클릭: 삭제"


func set_stops(s: Array) -> void:
	stops = []
	for x in s:
		stops.append([x[0], x[1]])
	queue_redraw()


func sample(t: float) -> Color:
	if stops.is_empty():
		return Color.BLACK
	if t <= stops[0][0]:
		return stops[0][1]
	for i in range(1, stops.size()):
		if t <= stops[i][0]:
			var a: Array = stops[i - 1]
			var b: Array = stops[i]
			return (a[1] as Color).lerp(b[1], inverse_lerp(a[0], b[0], t) if b[0] > a[0] else 1.0)
	return stops[-1][1]


func _draw() -> void:
	var w := size.x
	var cs := 6.0
	var x := 0.0
	while x < w:
		var y := 0.0
		while y < BAR_H:
			var odd := (int(x / cs) + int(y / cs)) % 2 == 1
			draw_rect(Rect2(x, y, minf(cs, w - x), minf(cs, BAR_H - y)), Color(0.42, 0.42, 0.42) if odd else Color(0.62, 0.62, 0.62))
			y += cs
		x += cs
	var px := 0.0
	while px < w:
		draw_rect(Rect2(px, 0, 2.0, BAR_H), sample(px / maxf(w, 1.0)))
		px += 2.0
	draw_rect(Rect2(0, 0, w, BAR_H), Color(0, 0, 0, 0.6), false)
	for i in stops.size():
		var sx: float = stops[i][0] * w
		var r := Rect2(sx - 4, BAR_H + 2, 8, MARK_H)
		var c: Color = stops[i][1]
		draw_rect(r, Color(c.r, c.g, c.b, 1.0))
		draw_rect(r, Color.WHITE if i == _sel else Color(0, 0, 0, 0.8), false, 2.0 if i == _sel else 1.0)


func _stop_at(x: float) -> int:
	var best := -1
	var bd := 7.0
	for i in stops.size():
		var d := absf(stops[i][0] * size.x - x)
		if d < bd:
			bd = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var idx := _stop_at(event.position.x)
		if event.button_index == MOUSE_BUTTON_RIGHT and idx >= 0 and stops.size() > 2:
			stops.remove_at(idx)
			_sel = -1
			queue_redraw()
			changed.emit(stops, true)
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if idx < 0:
			var t := clampf(event.position.x / size.x, 0.0, 1.0)
			stops.append([t, sample(t)])
			_sort()
			idx = _stop_at(event.position.x)
			changed.emit(stops, true)
		_sel = idx
		if event.double_click:
			_open_picker()
		else:
			_dragging = true
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dragging:
			_dragging = false
			_sort()
			changed.emit(stops, true)
		accept_event()
	elif event is InputEventMouseMotion and _dragging and _sel >= 0:
		stops[_sel][0] = clampf(event.position.x / size.x, 0.0, 1.0)
		queue_redraw()
		var sorted := _sorted_copy()
		changed.emit(sorted, false)
		accept_event()


func _sorted_copy() -> Array:
	var s := stops.duplicate()
	s.sort_custom(func(a, b): return a[0] < b[0])
	return s


func _sort() -> void:
	var cur: Array = stops[_sel] if _sel >= 0 and _sel < stops.size() else []
	stops.sort_custom(func(a, b): return a[0] < b[0])
	if not cur.is_empty():
		for i in stops.size():
			if is_same(stops[i], cur):
				_sel = i


func _open_picker() -> void:
	if _sel < 0:
		return
	if _popup == null:
		_popup = PopupPanel.new()
		_picker = ColorPicker.new()
		_picker.edit_alpha = true
		_popup.add_child(_picker)
		add_child(_popup)
		_picker.color_changed.connect(func(c: Color):
			if _sel >= 0 and _sel < stops.size():
				stops[_sel][1] = c
				queue_redraw()
				changed.emit(stops, false))
		_popup.popup_hide.connect(func(): changed.emit(stops, true))
	_picker.color = stops[_sel][1]
	_popup.popup(Rect2i(Vector2i(get_screen_position() + Vector2(0, size.y)), Vector2i(10, 10)))
