## 미리보기 화면. 체커 배경 위에 렌더 결과를 띄우고, 베지어 키 포즈의 제어점을 드래그로 편집한다.
@tool
class_name VfxForgePreviewView
extends Control

signal point_dragged(index: int, uv: Vector2, final: bool)

var texture: Texture2D
var background := 0  # 0 체커, 1 검정, 2 흰색
var grid := Vector2i(1, 1)   # 시트 모드에서 칸 경계선 표시
## 베지어 제어점 4개 (uv). 비어 있으면 오버레이를 그리지 않는다.
var bezier_points: Array = []
var bezier_on_key := false

var _drag := -1


func _init() -> void:
	custom_minimum_size = Vector2(256, 256)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true


func display_rect() -> Rect2:
	var tex_size := Vector2(1, 1)
	if texture:
		tex_size = texture.get_size()
	var avail := size - Vector2(16, 16)
	var s := minf(avail.x / tex_size.x, avail.y / tex_size.y)
	var ds := tex_size * s
	return Rect2((size - ds) * 0.5, ds)


func uv_to_local(uv: Vector2) -> Vector2:
	var r := display_rect()
	return r.position + uv * r.size


func local_to_uv(p: Vector2) -> Vector2:
	var r := display_rect()
	return (p - r.position) / r.size


func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.11))
	var r := display_rect()
	match background:
		0:
			var cs := 16.0
			var y := 0.0
			while y < r.size.y:
				var x := 0.0
				while x < r.size.x:
					var odd := (int(x / cs) + int(y / cs)) % 2 == 1
					draw_rect(Rect2(r.position + Vector2(x, y), Vector2(minf(cs, r.size.x - x), minf(cs, r.size.y - y))), Color(0.2, 0.2, 0.22) if odd else Color(0.27, 0.27, 0.3))
					x += cs
				y += cs
		1:
			draw_rect(r, Color.BLACK)
		2:
			draw_rect(r, Color.WHITE)
	if texture:
		draw_texture_rect(texture, r, false)
	if grid.x > 1 or grid.y > 1:
		for i in range(1, grid.x):
			var x := r.position.x + r.size.x * i / grid.x
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.18))
		for i in range(1, grid.y):
			var y := r.position.y + r.size.y * i / grid.y
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.18))
	draw_rect(r, Color(1, 1, 1, 0.12), false)
	if bezier_points.size() == 4:
		_draw_bezier()


func _draw_bezier() -> void:
	var p: Array = []
	for q in bezier_points:
		p.append(uv_to_local(q))
	var col := Color(1.0, 0.85, 0.2) if bezier_on_key else Color(0.6, 0.85, 1.0)
	var pts := PackedVector2Array()
	for i in 41:
		var s := i / 40.0
		var u := 1.0 - s
		pts.append(u * u * u * p[0] + 3.0 * u * u * s * p[1] + 3.0 * u * s * s * p[2] + s * s * s * p[3])
	draw_polyline(pts, Color(col, 0.7), 1.5, true)
	draw_line(p[0], p[1], Color(1, 1, 1, 0.45), 1.0, true)
	draw_line(p[3], p[2], Color(1, 1, 1, 0.45), 1.0, true)
	for i in 4:
		var rad := 7.0 if i == 0 or i == 3 else 5.0
		draw_circle(p[i], rad + 1.5, Color(0, 0, 0, 0.7))
		draw_circle(p[i], rad, col if (i == 0 or i == 3) else Color.WHITE)
	var font := get_theme_default_font()
	draw_string(font, p[0] + Vector2(10, -8), "꼬리 쪽", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	draw_string(font, p[3] + Vector2(10, -8), "머리 쪽", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))


func _gui_input(event: InputEvent) -> void:
	if bezier_points.size() != 4:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = -1
			var best := 14.0
			for i in 4:
				var d: float = uv_to_local(bezier_points[i]).distance_to(event.position)
				if d < best:
					best = d
					_drag = i
			if _drag >= 0:
				accept_event()
		elif _drag >= 0:
			point_dragged.emit(_drag, local_to_uv(event.position), true)
			_drag = -1
			accept_event()
	elif event is InputEventMouseMotion and _drag >= 0:
		point_dragged.emit(_drag, local_to_uv(event.position), false)
		accept_event()
