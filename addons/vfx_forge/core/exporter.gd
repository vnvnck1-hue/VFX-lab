## PNG/스프라이트 시트 내보내기, 임포트 설정, 게임용 리소스(SpriteFrames, 파티클 머티리얼) 생성, 이음새 검사.
@tool
class_name VfxForgeExporter
extends RefCounted

const MAX_SHEET_PX := 8192


## 내보내기. 결과: {"ok", "error", "path", "files": [생성된 파일], "size": Vector2i}
static func export_graph(renderer: VfxForgeRenderer, graph: VfxForgeGraph, png_path := "") -> Dictionary:
	var s: Dictionary = graph.settings
	var path := png_path if png_path != "" else str(s.export_path)
	if path == "":
		return {"ok": false, "error": "내보낼 경로가 없습니다."}
	if path.get_extension().to_lower() != "png":
		path += ".png"
	var fs := int(s.frame_size)
	var size := Vector2i(fs * int(s.cols), fs * int(s.rows))
	if size.x > MAX_SHEET_PX or size.y > MAX_SHEET_PX:
		return {"ok": false, "error": "시트가 너무 큽니다 (%dx%d). 프레임 크기나 칸 수를 줄이세요. 최대 %d px." % [size.x, size.y, MAX_SHEET_PX]}

	var img: Image = await renderer.render_image()
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	if err != OK:
		return {"ok": false, "error": "PNG 저장 실패 (%s): %s" % [error_string(err), path]}
	var files := [path]
	write_import_settings(path, s)
	if path.begins_with("res://"):
		if s.make_sprite_frames:
			files.append(write_sprite_frames(path, s))
		if s.make_particle_material:
			files.append(write_particle_material(path, s))
	return {"ok": true, "error": "", "path": path, "files": files, "size": size}


## .import 파일에 용도에 맞는 임포트 옵션을 써 둔다. 처음 임포트될 때 Godot 가 이 값을 읽는다.
static func write_import_settings(png_path: String, s: Dictionary) -> void:
	var ipath := png_path + ".import"
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(ipath):
		cfg.load(ipath)
	cfg.set_value("remap", "importer", "texture")
	cfg.set_value("remap", "type", "CompressedTexture2D")
	if s.import_preset == "3d":
		cfg.set_value("params", "compress/mode", 2)       # VRAM 압축
		cfg.set_value("params", "mipmaps/generate", true)
	else:
		cfg.set_value("params", "compress/mode", 0)       # 무손실
		cfg.set_value("params", "mipmaps/generate", false)
	cfg.set_value("params", "detect_3d/compress_to", 0)
	cfg.set_value("params", "process/fix_alpha_border", true)
	cfg.set_value("params", "process/premult_alpha", false)
	cfg.save(ipath)


static func _blend_index(s: Dictionary) -> int:
	match s.blend:
		"add":
			return 1
		"premult":
			return 4
	return 0


## AnimatedSprite2D 에 바로 넣을 수 있는 SpriteFrames (.tres)
static func write_sprite_frames(png_path: String, s: Dictionary) -> String:
	var out_path := png_path.get_basename() + "_frames.tres"
	var fs := int(s.frame_size)
	var lines := PackedStringArray()
	lines.append("[gd_resource type=\"SpriteFrames\" format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"Texture2D\" path=\"%s\" id=\"1_sheet\"]" % png_path)
	lines.append("")
	var frames := PackedStringArray()
	for r in int(s.rows):
		for c in int(s.cols):
			var sid := "atlas_%d" % (r * int(s.cols) + c)
			lines.append("[sub_resource type=\"AtlasTexture\" id=\"%s\"]" % sid)
			lines.append("atlas = ExtResource(\"1_sheet\")")
			lines.append("region = Rect2(%d, %d, %d, %d)" % [c * fs, r * fs, fs, fs])
			lines.append("")
			frames.append("{\n\"duration\": 1.0,\n\"texture\": SubResource(\"%s\")\n}" % sid)
	lines.append("[resource]")
	lines.append("animations = [{\n\"frames\": [%s],\n\"loop\": %s,\n\"name\": &\"default\",\n\"speed\": %s\n}]" % [", ".join(frames), "true" if s.loop else "false", str(float(s.fps))])
	_write_text(out_path, "\n".join(lines) + "\n")
	return out_path


## 파티클용 머티리얼. 2D = CanvasItemMaterial, 3D = 빌보드 StandardMaterial3D
static func write_particle_material(png_path: String, s: Dictionary) -> String:
	var out_path := png_path.get_basename() + "_particle.tres"
	var lines := PackedStringArray()
	if s.import_preset == "3d":
		lines.append("[gd_resource type=\"StandardMaterial3D\" format=3]")
		lines.append("")
		lines.append("[ext_resource type=\"Texture2D\" path=\"%s\" id=\"1_sheet\"]" % png_path)
		lines.append("")
		lines.append("[resource]")
		lines.append("transparency = 1")
		lines.append("blend_mode = %d" % _blend_index(s))
		lines.append("shading_mode = 0")
		lines.append("vertex_color_use_as_albedo = true")
		lines.append("albedo_texture = ExtResource(\"1_sheet\")")
		lines.append("billboard_mode = 3")
	else:
		lines.append("[gd_resource type=\"CanvasItemMaterial\" format=3]")
		lines.append("")
		lines.append("[resource]")
		lines.append("blend_mode = %d" % _blend_index(s))
		lines.append("particles_animation = true")
	lines.append("particles_anim_h_frames = %d" % int(s.cols))
	lines.append("particles_anim_v_frames = %d" % int(s.rows))
	lines.append("particles_anim_loop = %s" % ("true" if s.loop else "false"))
	_write_text(out_path, "\n".join(lines) + "\n")
	return out_path


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)


# ================= 이음새 검사 =================

## 가장자리 픽셀 차이가 내부 인접 픽셀 차이보다 확연히 크면 이음새로 본다.
## 반환: 0 이상 = 이음새 정도 (1 이상이면 이음새)
static func seam_score(img: Image, axis: int) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var edge := 0.0
	var inner := 0.0
	var n := h if axis == 0 else w
	var step := maxi(1, n / 256)
	var cnt := 0
	for i in range(0, n, step):
		var a: Color
		var b: Color
		var c: Color
		var d: Color
		if axis == 0:
			a = img.get_pixel(0, i)
			b = img.get_pixel(w - 1, i)
			c = img.get_pixel(w / 2, i)
			d = img.get_pixel(w / 2 - 1, i)
		else:
			a = img.get_pixel(i, 0)
			b = img.get_pixel(i, h - 1)
			c = img.get_pixel(i, h / 2)
			d = img.get_pixel(i, h / 2 - 1)
		edge += _cdiff(a, b)
		inner += _cdiff(c, d)
		cnt += 1
	edge /= cnt
	inner /= cnt
	return edge / (inner * 2.5 + 0.01)


static func _cdiff(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)) * 0.25


static func _image_has_seam(img: Image, tiling: Vector2) -> Array:
	var axes := []
	if tiling.x > 0.5 and seam_score(img, 0) >= 1.0:
		axes.append("가로")
	if tiling.y > 0.5 and seam_score(img, 1) >= 1.0:
		axes.append("세로")
	return axes


## 결과: {"ok": 이음새 없음, "message", "node": 원인 노드 id 또는 -1}
static func check_seams(renderer: VfxForgeRenderer, graph: VfxForgeGraph) -> Dictionary:
	var tiling := graph.tiling()
	if tiling == Vector2.ZERO:
		return {"ok": true, "message": "용도가 '이펙트'라 타일링 검사를 하지 않습니다. 용도를 띠(Strip)나 타일(Tile)로 바꾸세요.", "node": -1}
	var prev_target := renderer.target_id
	var frames_to_check := [0]
	if graph.frame_count() > 1:
		frames_to_check.append(graph.frame_count() / 2)
	var result := {"ok": true, "message": "이음새가 없습니다.", "node": -1}
	renderer.target_id = -1
	renderer.recompile()
	var bad_axes := []
	for f in frames_to_check:
		var img: Image = await renderer.render_image(f)
		bad_axes = _image_has_seam(img, tiling)
		if not bad_axes.is_empty():
			break
	if not bad_axes.is_empty():
		result = {"ok": false, "message": "%s 방향 이음새가 있습니다." % "/".join(bad_axes), "node": -1}
		# 의존 순서대로 노드를 하나씩 미리보기해서 처음 이음새가 생기는 노드를 찾는다
		var order := VfxForgeCompiler._topo_order(graph, graph.output_node())
		for id in order:
			var def := VfxForgeCompiler.Lib.get_def(graph.nodes[id].type)
			if def.outputs[0].type == VfxForgeCompiler.Lib.UV:
				continue
			renderer.target_id = id
			renderer.recompile()
			var img: Image = await renderer.render_image(frames_to_check[0])
			if not _image_has_seam(img, tiling).is_empty():
				result.node = id
				result.message += " 원인으로 보이는 노드: %s (#%d)" % [def.title, id]
				break
	renderer.target_id = prev_target
	renderer.recompile()
	return result
