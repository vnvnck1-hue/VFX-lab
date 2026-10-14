## 카드 번(Card Burn) 데모용 카드 텍스처를 만든다. 실행:
##   Godot --headless --path . --script res://tools/build_card_texture.gd
## 흰 바탕 + 검은 테두리 + 안쪽 장식선 + 가운데 다이아 문양. SDF 로 그려서 가장자리가 부드럽다.
extends SceneTree

const W := 400
const H := 560
const OUT := "res://vfx/card_burn/card.png"


func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var half := Vector2(W, H) * 0.5
	for y in H:
		for x in W:
			var p := Vector2(x + 0.5, y + 0.5) - half
			# 카드 외곽 (둥근 사각형)
			var d_card := _sd_round_box(p, half - Vector2(2, 2), 30.0)
			var a := clampf(0.5 - d_card, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var ink := 0.0
			# 바깥 검은 테두리
			ink = maxf(ink, _cov(-(d_card + 12.0)))
			# 안쪽 장식선 2줄
			var d_in := _sd_round_box(p, half - Vector2(34, 34), 14.0)
			ink = maxf(ink, _cov(absf(d_in) - 2.5))
			var d_in2 := _sd_round_box(p, half - Vector2(44, 44), 8.0)
			ink = maxf(ink, _cov(absf(d_in2) - 1.0))
			# 네 귀퉁이 작은 다이아
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var q: Vector2 = p - c * (half - Vector2(34, 34))
				ink = maxf(ink, _cov(absf(q.x) + absf(q.y) - 11.0))
			# 가운데 문양: 다이아 + 안쪽 흰 다이아 + 원
			var dia := absf(p.x) / 70.0 + absf(p.y) / 105.0 - 1.0
			var dia_in := absf(p.x) / 38.0 + absf(p.y) / 58.0 - 1.0
			var circ := p.length() - 14.0
			var sym := _cov(dia * 70.0) * (1.0 - _cov(dia_in * 38.0))
			sym = maxf(sym, _cov(circ))
			ink = maxf(ink, sym)
			var v := 1.0 - ink
			img.set_pixel(x, y, Color(v, v, v, a))
	img.save_png(OUT)
	print("saved ", OUT)
	quit()


func _cov(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)


func _sd_round_box(p: Vector2, b: Vector2, r: float) -> float:
	var q := p.abs() - b + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
