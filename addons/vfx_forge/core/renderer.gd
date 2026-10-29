## 컴파일된 셰이더를 SubViewport 에 그리는 렌더러.
## 미리보기는 viewport 텍스처를 그대로 화면에 띄우고, 내보내기는 시트 전체를 한 번에 그려 Image 로 읽는다.
@tool
class_name VfxForgeRenderer
extends Node

const Lib := preload("res://addons/vfx_forge/core/node_library.gd")

signal compiled(ok: bool, message: String)

var viewport: SubViewport
var rect: ColorRect
var material := ShaderMaterial.new()
var shader := Shader.new()
var graph: VfxForgeGraph
var target_id := -1
var last_code := ""
## 현재 셰이더에 있는 uniform 이름 -> {"type", "node", "param"}
var _uniforms := {}
var _grad_tex := {}


func _init() -> void:
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	rect = ColorRect.new()
	rect.size = Vector2(512, 512)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)


func get_texture() -> Texture2D:
	return viewport.get_texture()


func set_graph(g: VfxForgeGraph, preview_target := -1) -> bool:
	graph = g
	target_id = preview_target
	return recompile()


func recompile() -> bool:
	var res := VfxForgeCompiler.compile(graph, target_id)
	if not res.ok:
		compiled.emit(false, res.error)
		return false
	if res.code != last_code:
		last_code = res.code
		# 이미 머티리얼에 붙은 Shader 의 code 만 바꾸면 반영되지 않는 경우가 있어 매번 새로 만들어 붙인다
		shader = Shader.new()
		shader.code = res.code
		material.shader = shader
	_uniforms.clear()
	for u in res.uniforms:
		_uniforms[u.name] = u
	for u in res.uniforms:
		_apply_uniform(u.name)
	compiled.emit(true, "")
	return true


## 파라미터 값 하나만 바뀌었을 때 (재컴파일 없음)
func update_param(node_id: int, param: String) -> void:
	var un := VfxForgeCompiler.uniform_name(node_id, param)
	if _uniforms.has(un):
		_apply_uniform(un)


func _apply_uniform(un: String) -> void:
	var u: Dictionary = _uniforms[un]
	if not graph.nodes.has(u.node):
		return
	var v = graph.nodes[u.node].params[u.param]
	match u.type:
		"bool":
			material.set_shader_parameter(un, 1.0 if v else 0.0)
		"gradient":
			material.set_shader_parameter(un, _gradient_texture(un, v))
		"bezier":
			_apply_bezier(un, v)
		_:
			material.set_shader_parameter(un, v)


func _gradient_texture(un: String, stops: Array) -> GradientTexture1D:
	var tex: GradientTexture1D = _grad_tex.get(un)
	if tex == null:
		tex = GradientTexture1D.new()
		tex.width = 256
		tex.gradient = Gradient.new()
		_grad_tex[un] = tex
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	tex.gradient.offsets = offsets
	tex.gradient.colors = colors
	return tex


func _apply_bezier(un: String, keys: Array) -> void:
	var pts := PackedVector2Array()
	var data := PackedVector4Array()
	var times := PackedFloat32Array()
	var n := mini(keys.size(), Lib.MAX_BEZIER_KEYS)
	for i in Lib.MAX_BEZIER_KEYS:
		var k: Dictionary = keys[mini(i, n - 1)] if n > 0 else {"t": 0.0, "p": [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], "head": 0.0, "tail": 0.0, "width": 0.0}
		for j in 4:
			pts.append(k.p[j])
		data.append(Vector4(k.head, k.tail, k.width, 0.0))
		times.append(k.t if i < n else 2.0)
	material.set_shader_parameter(un + "_p", pts)
	material.set_shader_parameter(un + "_d", data)
	material.set_shader_parameter(un + "_t", times)
	material.set_shader_parameter(un + "_n", maxi(n, 1))


## 전역 값 (설정, 시간, 시트/미리보기 모드)
func set_globals(t: float, sheet: bool, size: Vector2i, preview_repeat := 1.0) -> void:
	var s: Dictionary = graph.settings
	material.set_shader_parameter("vfx_t", t)
	material.set_shader_parameter("vfx_sheet", 1 if sheet else 0)
	material.set_shader_parameter("vfx_cols", int(s.cols))
	material.set_shader_parameter("vfx_rows", int(s.rows))
	material.set_shader_parameter("vfx_loop", 1.0 if s.loop else 0.0)
	material.set_shader_parameter("vfx_tiling", graph.tiling())
	material.set_shader_parameter("vfx_preview_repeat", preview_repeat)
	# 안티에일리어싱 폭은 실제 출력 해상도 기준으로 맞춘다
	material.set_shader_parameter("vfx_frame_px", float(s.frame_size))
	if viewport.size != size:
		viewport.size = size
		rect.size = Vector2(size)


## 시트 전체(또는 frame >= 0 이면 그 프레임 하나)를 최종 해상도로 그려서 Image 로 돌려준다.
func render_image(frame := -1) -> Image:
	var s: Dictionary = graph.settings
	var fs := int(s.frame_size)
	var prev_size := viewport.size
	if frame >= 0:
		set_globals(graph.frame_time(frame), false, Vector2i(fs, fs))
	else:
		set_globals(0.0, true, Vector2i(fs * int(s.cols), fs * int(s.rows)))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 크기가 바뀐 뒤 렌더 타깃이 다시 만들어지고 한 번 더 그려질 때까지 기다린다
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	viewport.size = prev_size
	rect.size = Vector2(prev_size)
	return img
