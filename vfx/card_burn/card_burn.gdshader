// 카드 번(Card Burn): 카드가 한쪽 끝부터 타 들어가는 2D 셰이더.
// Sprite2D / TextureRect 에 넣고 burn_progress 를 0 → 1 로 올리면 된다.
//
// 연소선 기준 층 구조 (탄 쪽 → 남은 카드 쪽):
//   [탄 부분 = 투명 또는 그을음] | [외곽선(검정)] | [불꽃(하늘색)] | [카드]
// 텍스처는 shrink_factor 만큼 줄여서 그리고, 남는 여백은 불꽃이 카드 밖으로 삐져나가는 자리로 쓴다.
shader_type canvas_item;

group_uniforms Burn;
/** 0 = 온전한 카드, 1 = 완전히 타서 사라짐 */
uniform float burn_progress : hint_range(0.0, 1.0, 0.001) = 0.0;
/** 이미 탄 부분에 남는 그을음 잔상의 불투명도 (0이면 완전히 사라짐) */
uniform float burnt_alpha : hint_range(0.0, 1.0, 0.01) = 0.0;
/** 켜면 위에서 아래로, 끄면 아래에서 위로 탄다 */
uniform bool burn_from_top = false;

group_uniforms Colors;
uniform vec4 flame_color : source_color = vec4(0.55, 0.87, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
/** 불꽃 색을 HDR로 밝게 (1 = 그대로). 2D HDR/Glow 를 켠 씬에서 번짐이 생긴다 */
uniform float flame_brightness : hint_range(1.0, 8.0, 0.1) = 1.0;

group_uniforms Band;
/** 불타는 띠 전체 두께 (카드 높이 대비) */
uniform float fire_thickness : hint_range(0.0, 0.4, 0.001) = 0.14;
/** 띠 중 불꽃이 차지하는 비율 (%) */
uniform float flame_percent : hint_range(0.0, 100.0, 0.1) = 80.0;
/** 띠 중 검은 외곽선이 차지하는 비율 (%) */
uniform float outline_percent : hint_range(0.0, 100.0, 0.1) = 20.0;

group_uniforms Noise;
/** 불꽃 일렁임 속도 */
uniform float speed : hint_range(0.0, 20.0, 0.01) = 7.0;
/** 불꽃 끝(혀 모양) 노이즈 촘촘함 */
uniform float noise_scale : hint_range(0.5, 40.0, 0.01) = 10.0;
/** 연소선 노이즈 촘촘함 */
uniform float burn_noise_scale : hint_range(0.5, 40.0, 0.01) = 11.0;
/** 연소선의 큰 굴곡 (완만한 물결) */
uniform float edge_wobble : hint_range(0.0, 1.0, 0.001) = 0.3;
/** 연소선의 잔 톱니/흘러내림 */
uniform float edge_jaggedness : hint_range(0.0, 1.0, 0.001) = 0.164;
/** 노이즈의 잔 디테일 양. 0 = 매끈한 덩어리, 1 = 삐죽삐죽 거친 가장자리 */
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.15;
/** 경계선 블러 폭 (화면 픽셀). 클수록 가장자리가 부드럽게 번진다 */
uniform float edge_softness : hint_range(0.5, 8.0, 0.1) = 1.5;

group_uniforms Layout;
/** 카드를 쿼드 안에서 줄이는 비율. 남는 여백에 불꽃이 삐져나간다 */
uniform float shrink_factor : hint_range(0.3, 1.0, 0.01) = 0.85;
/** 카드 모서리 둥글기 (텍스처 픽셀). 불꽃이 카드 모양을 따라가게 하는 마스크용 */
uniform float corner_radius : hint_range(0.0, 100.0, 1.0) = 30.0;

// 정수 해시: 실수 해시는 GPU 반올림 오차로 격자 경계에서 값이 어긋나 세로 단차가 생긴다
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic: 격자 이음매 없이 매끈하게
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// gain 이 작을수록 고주파 옥타브가 약해져서 매끈해진다 (결과는 0~1 로 정규화)
float fbm(vec2 p, float gain) {
	float v = 0.0;
	float amp = 1.0;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		total += amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= gain;
	}
	return v / total;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// 경계를 edge_softness 픽셀 폭으로 부드럽게 (툰 느낌은 유지하면서 계단 현상 제거)
float aa_step(float edge, float x) {
	float w = max(fwidth(x) * edge_softness, 1e-5);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	float aspect = tex_size.x / tex_size.y;
	float t = TIME * speed * 0.1;

	// 쿼드 UV → 카드 UV (가운데 기준으로 shrink_factor 만큼 축소)
	vec2 c = (UV - 0.5) / shrink_factor + 0.5;
	vec4 card = texture(TEXTURE, c);
	card.a *= step(0.0, c.x) * step(c.x, 1.0) * step(0.0, c.y) * step(c.y, 1.0);

	// h: 타기 시작하는 쪽에서 잰 높이 (0 = 시작 변, 1 = 반대 변)
	float h = burn_from_top ? c.y : 1.0 - c.y;
	float x = c.x * aspect;

	// 연소선 왜곡: 큰 물결(wobble) + 2D 노이즈 톱니(jaggedness, 세로로 늘려서 흘러내리는 모양)
	float wob = (vnoise(vec2(x * burn_noise_scale * 0.25, t * 0.15)) - 0.5) * edge_wobble * 0.3;
	float gain = mix(0.05, 0.6, roughness);
	float jag = (fbm(vec2(x * burn_noise_scale, h * burn_noise_scale * 0.45 + t * 0.2), gain) - 0.5) * edge_jaggedness * 0.6;

	// burn_progress 0/1 에서 띠가 카드 밖으로 완전히 빠지도록 여유를 둔다
	float margin = fire_thickness + edge_wobble * 0.15 + edge_jaggedness * 0.3 + 0.02;
	float line = mix(-margin, 1.0 + margin, burn_progress);
	float e = h - line + wob + jag;   // e < 0 : 탄 부분

	// 띠 경계: 외곽선 끝, 불꽃 끝 (불꽃 끝은 위로 올라가는 노이즈로 혀처럼 일렁임)
	float outline_end = fire_thickness * outline_percent * 0.01;
	float flame_w = fire_thickness * flame_percent * 0.01;
	vec2 tp = vec2(x * noise_scale, h * noise_scale * 0.6 - t * 1.5);
	float tongue = fbm(tp, gain);
	float flame_end = outline_end + flame_w * (0.45 + 1.1 * tongue);

	// 불꽃/외곽선 마스크: 카드 모양을 약간 넓힌 영역 (여백으로 삐져나갈 수 있게)
	vec2 p_px = (c - 0.5) * tex_size;
	float spill = fire_thickness * tex_size.y * 0.1;
	float card_sd = sd_round_box(p_px, tex_size * 0.5, corner_radius);
	float band_mask = 1.0 - smoothstep(spill * 0.6, spill, card_sd + (tongue - 0.5) * spill);

	float not_burnt = aa_step(0.0, e);
	float past_outline = aa_step(outline_end, e);
	float past_flame = aa_step(flame_end, e);

	vec4 flame = vec4(flame_color.rgb * flame_brightness, flame_color.a);
	vec4 band = mix(outline_color, flame, past_outline);
	band.a *= band_mask;

	vec4 burnt = vec4(mix(card.rgb, outline_color.rgb, 0.85), card.a * burnt_alpha);

	vec4 col = mix(band, card, past_flame);
	col = mix(burnt, col, not_burnt);
	COLOR = col * COLOR;   // modulate / self_modulate 반영
}
