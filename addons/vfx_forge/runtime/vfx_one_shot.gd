## 게임에서 1회 재생 이펙트(슬래시, 임팩트, 충격파 등)를 띄우고 끝나면 스스로 지우는 AnimatedSprite2D.
##
##   VfxOneShot.spawn(self, preload("res://vfx_textures/impact_burst_frames.tres"), hit_pos)
##   VfxOneShot.spawn(self, slash_frames, pos, 0.6, attack_dir.angle())
class_name VfxOneShot
extends AnimatedSprite2D

## true 면 Add 블렌드 (빛나는 이펙트). 연기처럼 어두운 이펙트는 false.
@export var additive := true


static func spawn(parent: Node, frames: SpriteFrames, global_pos: Vector2, scale_factor := 1.0, angle := 0.0, add_blend := true) -> VfxOneShot:
	var fx := VfxOneShot.new()
	fx.sprite_frames = frames
	fx.additive = add_blend
	parent.add_child(fx)
	fx.global_position = global_pos
	fx.scale = Vector2.ONE * scale_factor
	fx.rotation = angle
	return fx


func _ready() -> void:
	if additive:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat
	animation_finished.connect(queue_free)
	# 루프 애니메이션이면 한 바퀴 돌고 끝낸다
	if sprite_frames and sprite_frames.get_animation_loop(animation):
		animation_looped.connect(queue_free)
	play()
