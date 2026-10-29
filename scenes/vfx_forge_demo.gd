## VFX Forge 로 내보낸 텍스처를 게임에서 쓰는 방법 모음.
## 클릭: 그 자리에 슬래시 + 임팩트 + 충격파 (1회 재생, VfxOneShot)
extends Node2D

const DIR := "res://vfx_textures/"

var _t := 0.0
var _circle: Sprite2D
var _flare: Sprite2D
var _trail: Line2D
var _auto_timer := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.1)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	# 1) 루프 플립북: AnimatedSprite2D + 내보낸 _frames.tres
	_loop_sprite("fire_loop", Vector2(110, 150), 0.42, "불꽃 루프")
	_loop_sprite("lightning_bolt", Vector2(260, 150), 0.42, "번개")
	_loop_sprite("energy_orb", Vector2(410, 150), 0.42, "에너지 구슬")
	_loop_sprite("portal_swirl", Vector2(560, 150), 0.42, "포털")
	_loop_sprite("heal_sparkles", Vector2(710, 150), 0.42, "회복 반짝이")
	var caustics := _loop_sprite("caustics_tile", Vector2(860, 150), 0.82, "커스틱 (타일)", false)
	caustics.modulate = Color(1, 1, 1, 0.9)

	# 2) 단일 이미지: 마법진은 회전, 플레어는 깜빡임
	_circle = _sprite("magic_circle", Vector2(1080, 170), 0.27, "마법진 (회전)")
	_flare = _sprite("star_flare", Vector2(1080, 470), 0.5, "플레어")

	# 3) 파티클: GPUParticles2D + 내보낸 _particle.tres (수명 동안 시트를 한 번 재생)
	var smoke := GPUParticles2D.new()
	smoke.texture = load(DIR + "smoke_puff.png")
	smoke.material = load(DIR + "smoke_puff_particle.tres")
	smoke.amount = 10
	smoke.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 60.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.25
	pm.scale_max = 0.4
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 20.0
	smoke.process_material = pm
	smoke.position = Vector2(150, 560)
	add_child(smoke)
	_label("파티클 연기 (GPUParticles2D)", Vector2(150, 640))

	# 4) 트레일: 가로 반복 텍스처를 Line2D 에 타일로
	_trail = Line2D.new()
	_trail.texture = load(DIR + "trail_strip.png")
	_trail.texture_mode = Line2D.LINE_TEXTURE_TILE
	_trail.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_trail.width = 60
	var tm := CanvasItemMaterial.new()
	tm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = tm
	add_child(_trail)
	_label("트레일 (Line2D + 띠 텍스처)", Vector2(470, 640))

	_label("클릭: 슬래시 + 임팩트 + 충격파 (VfxOneShot)", Vector2(800, 660))


func _loop_sprite(name: String, pos: Vector2, s: float, label: String, add := true) -> AnimatedSprite2D:
	var a := AnimatedSprite2D.new()
	a.sprite_frames = load(DIR + name + "_frames.tres")
	a.position = pos
	a.scale = Vector2.ONE * s
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		a.material = m
	a.play()
	add_child(a)
	_label(label, pos + Vector2(0, 120))
	return a


func _sprite(name: String, pos: Vector2, s: float, label: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(DIR + name + ".png")
	sp.position = pos
	sp.scale = Vector2.ONE * s
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = m
	add_child(sp)
	_label(label, pos + Vector2(0, 150))
	return sp


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos - Vector2(100, 0)
	l.size = Vector2(200, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.7)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_circle.rotation += delta * 0.4
	_flare.scale = Vector2.ONE * (0.45 + 0.08 * sin(_t * 5.0))
	_flare.rotation = sin(_t * 0.7) * 0.2
	# 8자 궤적을 그리는 트레일
	var pts := PackedVector2Array()
	for i in 40:
		var tt := _t * 1.6 - i * 0.04
		pts.append(Vector2(470 + sin(tt) * 150, 500 + sin(tt * 2.0) * 60))
	_trail.points = pts
	# 데모 녹화용: 주기적으로 자동 타격
	_auto_timer -= delta
	if _auto_timer <= 0.0:
		_auto_timer = 1.4
		_hit(Vector2(850, 480) + Vector2(randf_range(-60, 60), randf_range(-40, 40)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hit(event.position)


func _hit(pos: Vector2) -> void:
	VfxOneShot.spawn(self, load(DIR + "slash_arc_frames.tres"), pos, 0.5, randf_range(-0.6, 0.6))
	VfxOneShot.spawn(self, load(DIR + "impact_burst_frames.tres"), pos, 0.35)
	VfxOneShot.spawn(self, load(DIR + "shockwave_frames.tres"), pos, 0.6)
