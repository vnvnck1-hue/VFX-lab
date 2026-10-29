// VFX Forge 공용 셰이더 라이브러리.
// 컴파일러가 만든 셰이더가 #include 해서 쓴다. 노드 템플릿은 여기 함수를 호출한다.
// 좌표계: uv 는 프레임 하나 기준 0..1, y 는 아래 방향 (텍스처 좌표와 같음).

// ---- 컴파일러/렌더러가 채우는 전역 값 ----
uniform float vfx_t = 0.0;            // 미리보기 단일 프레임의 시간 (0..1)
uniform int vfx_sheet = 0;            // 1 = 스프라이트 시트 전체를 한 번에 그림
uniform int vfx_cols = 1;
uniform int vfx_rows = 1;
uniform float vfx_frame_px = 512.0;   // 프레임 한 칸의 픽셀 크기
uniform float vfx_loop = 1.0;         // 1 = 루프 (마지막 프레임 다음이 첫 프레임)
uniform vec2 vfx_tiling = vec2(0.0);  // 축별 타일링 (1 = 그 축으로 이음새 없이 반복)
uniform float vfx_preview_repeat = 1.0; // 미리보기에서 타일 반복 횟수

float vfx_px() { return 1.0 / vfx_frame_px; }

// 루프일 때는 정수 주기로 반올림해서 마지막 프레임과 첫 프레임이 이어지게 한다.
float vfx_cyc(float x) { return mix(x, round(x), vfx_loop); }

// 타일링 축에서는 가장 가까운 반복 사본까지의 차이를 쓴다 (도형이 가장자리를 넘어가면 반대편에서 나옴).
vec2 vfx_wrap_delta(vec2 d) { return mix(d, d - round(d), vfx_tiling); }

// 부호 거리(sdf) → 안티에일리어싱된 마스크. softness 는 uv 단위 페더 폭.
float vfx_fill(float d, float softness) {
	float w = max(softness, vfx_px()) * 0.5;
	return 1.0 - smoothstep(-w, w, d);
}

vec2 vfx_rot(vec2 p, float turns) {
	float a = turns * TAU;
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float vfx_lum(vec4 c) { return dot(c.rgb, vec3(0.299, 0.587, 0.114)) * c.a; }

// ---- 해시 (정수 기반: GPU 마다 결과가 같고 격자 경계에서 어긋나지 않음) ----
uint vfx_hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float vfx_hash3(ivec3 p, int seed) {
	uint h = vfx_hash_u(uint(p.x) * 1597334677u ^ vfx_hash_u(uint(p.y) * 3812015801u ^ vfx_hash_u(uint(p.z) * 2798796415u ^ uint(seed) * 2654435761u)));
	return float(h) / 4294967295.0;
}

float vfx_hash2(ivec2 p, int seed) { return vfx_hash3(ivec3(p, 0), seed); }
float vfx_hash1(int i, int seed) { return vfx_hash3(ivec3(i, 0, 0), seed); }

ivec3 vfx_wrap_cell(ivec3 c, ivec3 period) {
	return ivec3(mod(vec3(c), vec3(period)));
}

// ---- 주기성 그라디언트 노이즈 (3D). xy 는 공간, z 는 시간. 주기를 정수로 주면 이음새 없이 반복된다. ----
vec3 vfx_grad3(ivec3 c, ivec3 period, int seed) {
	ivec3 w = vfx_wrap_cell(c, period);
	float z = vfx_hash3(w, seed) * 2.0 - 1.0;
	float a = vfx_hash3(w, seed + 7919) * TAU;
	float r = sqrt(max(0.0, 1.0 - z * z));
	return vec3(r * cos(a), r * sin(a), z);
}

float vfx_perlin3(vec3 p, ivec3 period, int seed) {
	ivec3 i = ivec3(floor(p));
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(vfx_grad3(i + ivec3(0, 0, 0), period, seed), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(vfx_grad3(i + ivec3(1, 0, 0), period, seed), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(vfx_grad3(i + ivec3(0, 1, 0), period, seed), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(vfx_grad3(i + ivec3(1, 1, 0), period, seed), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(vfx_grad3(i + ivec3(0, 0, 1), period, seed), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(vfx_grad3(i + ivec3(1, 0, 1), period, seed), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(vfx_grad3(i + ivec3(0, 1, 1), period, seed), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(vfx_grad3(i + ivec3(1, 1, 1), period, seed), f - vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, u.x), x10 = mix(n010, n110, u.x);
	float x01 = mix(n001, n101, u.x), x11 = mix(n011, n111, u.x);
	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z) * 1.15;
}

// mode: 0 = 부드러움(fbm), 1 = 능선(ridged), 2 = 난류(billow)
// 반환값 0..1
// tile: 이음새 없이 반복할 축 (전역 타일링 + 노드의 '가로 이음새 없음' 옵션)
float vfx_noise(vec2 uv, float scale, float stretch_y, float octaves, float persistence, float evolve, float t, int mode, int seed, vec2 tile) {
	vec2 sc = vec2(scale, scale * stretch_y);
	// 타일링 축은 정수 주기로 맞춘다
	sc = mix(sc, max(round(sc), vec2(1.0)), tile);
	float zp = max(round(vfx_cyc(evolve)), 1.0);
	float z = t * vfx_cyc(evolve);
	vec2 p = uv * sc;
	float amp = 1.0, total = 0.0, norm = 0.0;
	int oct = int(clamp(octaves, 1.0, 8.0));
	for (int o = 0; o < oct; o++) {
		ivec2 per_xy = ivec2(mix(vec2(65536.0), sc, tile));
		ivec3 per = ivec3(per_xy, int(mix(65536.0, zp, vfx_loop)));
		float n = vfx_perlin3(vec3(p, z), per, seed + o * 131);
		if (mode == 1) {
			n = 1.0 - abs(n);
			n = n * n;
		} else if (mode == 2) {
			n = abs(n);
		} else {
			n = n * 0.5 + 0.5;
		}
		total += n * amp;
		norm += amp;
		amp *= persistence;
		p *= 2.0;
		sc *= 2.0;
	}
	return clamp(total / max(norm, 1e-5), 0.0, 1.0);
}

// ---- 셀(보로노이) 노이즈. 반환: x = F1 거리, y = 경계(F2-F1), z = 셀마다 다른 랜덤값 ----
vec3 vfx_voronoi(vec2 uv, float scale, float stretch_y, float jitter, float anim, float t, int seed, vec2 tile) {
	vec2 sc = vec2(scale, scale * stretch_y);
	sc = mix(sc, max(round(sc), vec2(1.0)), tile);
	ivec3 per = ivec3(ivec2(mix(vec2(65536.0), sc, tile)), 1);
	vec2 p = uv * sc;
	ivec2 ci = ivec2(floor(p));
	vec2 f = fract(p);
	float d1 = 8.0, d2 = 8.0, id = 0.0;
	float ph = t * vfx_cyc(anim) * TAU;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec3 c = vfx_wrap_cell(ivec3(ci + ivec2(x, y), 0), per);
			float h1 = vfx_hash3(c, seed);
			float h2 = vfx_hash3(c, seed + 101);
			float h3 = vfx_hash3(c, seed + 202);
			vec2 o = vec2(h1, h2);
			o = 0.5 + (o - 0.5) * jitter + vec2(cos(ph + h3 * TAU), sin(ph + h3 * TAU)) * 0.25 * jitter * step(0.001, abs(anim));
			vec2 r = vec2(float(x), float(y)) + o - f;
			float d = length(r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = h3;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

// ---- 도형 SDF (uv 단위, 음수 = 안쪽) ----
float vfx_sd_circle(vec2 uv, vec2 c, float r) {
	return length(vfx_wrap_delta(uv - c)) - r;
}

// 정다각형/별. star = 0 이면 정다각형, 1 에 가까울수록 뾰족한 별.
float vfx_sd_star(vec2 uv, vec2 c, float r, float n, float star, float rot) {
	vec2 p = vfx_rot(vfx_wrap_delta(uv - c), -rot);
	n = max(n, 2.0);
	float sector = TAU / n;
	float a = atan(p.x, -p.y);
	a = mod(a + sector * 0.5, sector) - sector * 0.5;
	vec2 q = length(p) * vec2(abs(sin(a)), cos(a));
	vec2 tip = vec2(0.0, r);
	float ri = mix(r * cos(PI / n), r * 0.12, clamp(star, 0.0, 1.0));
	vec2 inn = ri * vec2(sin(sector * 0.5), cos(sector * 0.5));
	vec2 e = inn - tip;
	vec2 w = q - tip;
	float h = clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
	float d = length(w - e * h);
	float s = e.x * w.y - e.y * w.x;
	return s < 0.0 ? -d : d;
}

float vfx_sd_box(vec2 uv, vec2 c, vec2 half_size, float rot, float round_r) {
	vec2 p = vfx_rot(vfx_wrap_delta(uv - c), -rot);
	vec2 q = abs(p) - half_size + round_r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - round_r;
}

// 선분까지 거리와 선분 위 위치(0..1)
vec2 vfx_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return vec2(length(pa - ba * h), h);
}

// 두께가 a→b 로 변하는 선
float vfx_sd_line(vec2 uv, vec2 a, vec2 b, float w0, float w1) {
	vec2 s = vfx_seg(uv, a, b);
	return s.x - mix(w0, w1, s.y);
}

// 원을 n 개로 나눠 그 중 일부만 남기는 호(arc). 마법진 장식용.
float vfx_sd_arc(vec2 uv, vec2 c, float r, float thickness, float start, float len) {
	vec2 p = vfx_wrap_delta(uv - c);
	float a = fract(atan(p.y, p.x) / TAU + 1.0 - start);
	float ring = abs(length(p) - r) - thickness * 0.5;
	if (a <= len) {
		return ring;
	}
	vec2 e0 = c + r * vec2(cos(start * TAU), sin(start * TAU));
	vec2 e1 = c + r * vec2(cos((start + len) * TAU), sin((start + len) * TAU));
	return min(length(uv - e0), length(uv - e1)) - thickness * 0.5;
}

// ---- 그라데이션 ----
// mode: 0 선형, 1 방사형, 2 각도(원뿔), 3 다이아몬드
float vfx_gradient(vec2 uv, int mode, vec2 c, float angle, float scale) {
	vec2 p = uv - c;
	float g;
	if (mode == 0) {
		vec2 d = vec2(cos(angle * TAU), sin(angle * TAU));
		g = dot(p, d) * scale + 0.5;
	} else if (mode == 1) {
		g = length(p) * 2.0 * scale;
	} else if (mode == 2) {
		p = vfx_rot(p, -angle);
		g = fract(atan(p.y, p.x) / TAU + 1.0) * scale;
	} else {
		p = vfx_rot(p, -angle);
		g = (abs(p.x) + abs(p.y)) * 2.0 * scale;
	}
	return clamp(g, 0.0, 1.0);
}

// ---- 방사형 빛줄기 ----
float vfx_rays(vec2 uv, vec2 c, float count, float width, float len_min, float len_max, float rot, float jitter, float softness, int seed) {
	vec2 p = vfx_rot(uv - c, -rot);
	float r = length(p);
	float n = max(floor(count), 1.0);
	float a = fract(atan(p.y, p.x) / TAU + 1.0) * n;
	float best = 0.0;
	for (int k = -1; k <= 1; k++) {
		float id = floor(a) + float(k);
		int wid = int(mod(id, n));
		float off = (vfx_hash1(wid, seed) - 0.5) * jitter;
		float L = mix(len_min, len_max, vfx_hash1(wid, seed + 31));
		float w = width * mix(0.5, 1.0, vfx_hash1(wid, seed + 57));
		float da = (a - (id + 0.5 + off)) / n * TAU;
		float perp = abs(sin(clamp(da, -1.5, 1.5))) * r;
		float taper = clamp(1.0 - r / max(L, 1e-4), 0.0, 1.0);
		float d = perp - w * taper;
		float m = vfx_fill(d, softness) * step(abs(da), 1.5) * smoothstep(0.0, 0.02, taper);
		best = max(best, m);
	}
	return best;
}

// ---- 흩뿌린 파편/불티 ----
// progress 0..1 동안 중심에서 바깥으로 날아가며 작아진다.
float vfx_scatter(vec2 uv, vec2 c, float count, float dir, float spread, float r0, float travel, float size, float size_rand, float streak, float progress, float fade, int seed) {
	float best = 0.0;
	int n = int(clamp(count, 1.0, 64.0));
	for (int i = 0; i < 64; i++) {
		if (i >= n) {
			break;
		}
		float h1 = vfx_hash1(i, seed);
		float h2 = vfx_hash1(i, seed + 11);
		float h3 = vfx_hash1(i, seed + 23);
		float h4 = vfx_hash1(i, seed + 37);
		float ang = (dir + (h1 - 0.5) * spread) * TAU;
		vec2 d = vec2(cos(ang), sin(ang));
		float sp = mix(0.55, 1.0, h2);
		float pr = clamp(progress * mix(0.85, 1.15, h4), 0.0, 1.0);
		vec2 pos = c + d * (r0 + travel * sp * (1.0 - pow(1.0 - pr, 2.0)));
		float s = size * mix(1.0, h3, size_rand) * pow(1.0 - pr, fade);
		vec2 q = uv - pos;
		float along = dot(q, d);
		float across = dot(q, vec2(-d.y, d.x));
		float len = s * (1.0 + streak * (1.0 - pr));
		float dd = length(vec2(along / max(len / max(s, 1e-5), 1.0), across)) - s;
		best = max(best, vfx_fill(dd, s * 0.6));
	}
	return best;
}

// ---- 베지어 스트로크 (슬래시/검기) ----
vec2 vfx_bez(vec2 p0, vec2 p1, vec2 p2, vec2 p3, float s) {
	float u = 1.0 - s;
	return u * u * u * p0 + 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s * p3;
}

// 반환: x = 마스크, y = 진행 방향 위치(0 꼬리 → 1 머리), z = 가로 위치(-1..1), w = 거리장
vec4 vfx_bezier_stroke(vec2 uv, vec2 p0, vec2 p1, vec2 p2, vec2 p3, float head, float tail, float width, float taper, float peak, float softness) {
	const int N = 40;
	vec2 prev = p0;
	float best = 1e9;
	float best_s = 0.0;
	float best_side = 0.0;
	for (int i = 1; i <= N; i++) {
		float s1 = float(i) / float(N);
		vec2 cur = vfx_bez(p0, p1, p2, p3, s1);
		vec2 sg = vfx_seg(uv, prev, cur);
		if (sg.x < best) {
			best = sg.x;
			best_s = (float(i - 1) + sg.y) / float(N);
			vec2 e = cur - prev;
			vec2 w = uv - prev;
			best_side = sign(e.x * w.y - e.y * w.x);
		}
		prev = cur;
	}
	float span = max(head - tail, 1e-4);
	float local = (best_s - tail) / span;
	float pk = clamp(peak, 0.01, 0.99);
	float x = local < pk ? local / pk : (1.0 - local) / (1.0 - pk);
	x = clamp(x, 0.0, 1.0);
	float w = width * pow(sin(x * PI * 0.5), max(taper, 0.01));
	float inside = step(0.0, local) * step(local, 1.0);
	float d = best - w;
	float mask = vfx_fill(d, softness) * inside;
	float across = clamp(best * best_side / max(w, 1e-4), -1.0, 1.0);
	return vec4(mask, clamp(local, 0.0, 1.0), across, d);
}

// ---- 번개 ----
// 지그재그: 선형 보간 값 노이즈(각진 꺾임) 3옥타브
float vfx_zigzag(float s, float freq, int seed) {
	float total = 0.0, amp = 1.0, f = freq;
	for (int o = 0; o < 3; o++) {
		float x = s * f;
		int i = int(floor(x));
		float a = vfx_hash1(i, seed + o * 17) * 2.0 - 1.0;
		float b = vfx_hash1(i + 1, seed + o * 17) * 2.0 - 1.0;
		total += mix(a, b, fract(x)) * amp;
		amp *= 0.45;
		f *= 2.3;
	}
	return total;
}

// a→b 번개 한 줄기까지의 거리. 반환 x = 거리, y = 줄기 위 위치(0..1)
vec2 vfx_bolt_dist(vec2 uv, vec2 a, vec2 b, float amp, float freq, int seed) {
	vec2 d = b - a;
	float L = max(length(d), 1e-4);
	vec2 dir = d / L;
	vec2 nrm = vec2(-dir.y, dir.x);
	vec2 q = uv - a;
	float s = dot(q, dir) / L;
	float h = dot(q, nrm);
	float sc = clamp(s, 0.0, 1.0);
	float off = vfx_zigzag(sc, freq, seed) * amp * L * sin(sc * PI);
	float dist = abs(h - off);
	if (s < 0.0) {
		dist = length(q);
	} else if (s > 1.0) {
		dist = length(uv - b);
	}
	return vec2(dist, sc);
}

// 반환: x = 선명한 코어 마스크, y = 부드러운 글로우
vec2 vfx_lightning(vec2 uv, vec2 a, vec2 b, float amp, float freq, float width, float glow, float branches, int seed) {
	vec2 m = vfx_bolt_dist(uv, a, b, amp, freq, seed);
	float w = width * mix(1.0, 0.45, m.y);
	float dist = m.x - w;
	vec2 d = b - a;
	float L = length(d);
	vec2 dir = d / max(L, 1e-4);
	vec2 nrm = vec2(-dir.y, dir.x);
	int nb = int(clamp(branches, 0.0, 4.0));
	for (int k = 0; k < 4; k++) {
		if (k >= nb) {
			break;
		}
		float s0 = mix(0.2, 0.7, vfx_hash1(k, seed + 401));
		float off = vfx_zigzag(s0, freq, seed) * amp * L * sin(s0 * PI);
		vec2 start = a + d * s0 + nrm * off;
		float ang = mix(0.06, 0.14, vfx_hash1(k, seed + 409)) * (vfx_hash1(k, seed + 419) < 0.5 ? -1.0 : 1.0);
		vec2 bd = vfx_rot(dir, ang) * L * mix(0.25, 0.45, vfx_hash1(k, seed + 421));
		vec2 bm = vfx_bolt_dist(uv, start, start + bd, amp * 1.3, freq * 1.4, seed + 1000 + k * 77);
		float bw = width * 0.6 * mix(1.0, 0.2, bm.y);
		dist = min(dist, bm.x - bw);
	}
	float core = vfx_fill(dist, width * 0.35);
	float g = exp(-max(dist, 0.0) / max(glow, 1e-4));
	return vec2(core, g);
}

// ---- 룬 고리 (마법진 글자띠) ----
// 고리를 count 칸으로 나누고 칸마다 3x3 격자 위의 선분을 랜덤으로 골라 글자처럼 그린다.
float vfx_rune_ring(vec2 uv, vec2 c, float radius, float size, float count, float stroke, float density, float rot, int seed) {
	vec2 p = uv - c;
	float r = length(p);
	float n = max(floor(count), 1.0);
	float a = fract(atan(p.y, p.x) / TAU + 1.0 - rot) * n;
	int cell = int(mod(floor(a), n));
	float cw = TAU * radius / n;
	// 칸 안 좌표 (uv 단위, 칸 폭의 80% 만 사용해서 글자 사이 간격을 둔다)
	vec2 lp = vec2((fract(a) - 0.5) * cw, r - radius);
	vec2 gs = vec2(cw * 0.7, size);
	float best = 1e9;
	// 3x3 격자의 점 사이 선분 후보 20개
	for (int k = 0; k < 20; k++) {
		ivec2 ia;
		ivec2 ib;
		if (k < 6) {
			ia = ivec2(k % 2, k / 2);
			ib = ia + ivec2(1, 0);
		} else if (k < 12) {
			ia = ivec2((k - 6) % 3, (k - 6) / 3);
			ib = ia + ivec2(0, 1);
		} else if (k < 16) {
			ia = ivec2((k - 12) % 2, (k - 12) / 2);
			ib = ia + ivec2(1, 1);
		} else {
			ia = ivec2((k - 16) % 2 + 1, (k - 16) / 2);
			ib = ia + ivec2(-1, 1);
		}
		float prob = (k == 7) ? 0.85 : density;
		if (vfx_hash2(ivec2(cell, k), seed) > prob) {
			continue;
		}
		vec2 pa = (vec2(ia) / 2.0 - 0.5) * gs;
		vec2 pb = (vec2(ib) / 2.0 - 0.5) * gs;
		best = min(best, vfx_seg(lp, pa, pb).x);
	}
	return best - stroke * 0.5;
}

// ---- 시간 곡선 ----
// mode: 0 선형, 1 ease in, 2 ease out, 3 ease in-out, 4 smoothstep, 5 왕복(ping-pong), 6 펄스(구간 안에서 0→1→0)
float vfx_ease(float x, float start, float end, int mode, float power) {
	float k = clamp((x - start) / max(end - start, 1e-5), 0.0, 1.0);
	float p = max(power, 0.01);
	if (mode == 1) {
		return pow(k, p);
	} else if (mode == 2) {
		return 1.0 - pow(1.0 - k, p);
	} else if (mode == 3) {
		return k < 0.5 ? 0.5 * pow(2.0 * k, p) : 1.0 - 0.5 * pow(2.0 - 2.0 * k, p);
	} else if (mode == 4) {
		return k * k * (3.0 - 2.0 * k);
	} else if (mode == 5) {
		return pow(1.0 - abs(2.0 * k - 1.0), p);
	} else if (mode == 6) {
		return pow(sin(k * PI), p);
	}
	return k;
}

// ---- 블렌드 ----
// mode: 0 mix, 1 add, 2 subtract, 3 multiply, 4 screen, 5 max, 6 min, 7 difference, 8 overlay
float vfx_blend(float a, float b, int mode, float amount) {
	float r;
	if (mode == 1) {
		r = a + b;
	} else if (mode == 2) {
		r = a - b;
	} else if (mode == 3) {
		r = a * b;
	} else if (mode == 4) {
		r = 1.0 - (1.0 - a) * (1.0 - b);
	} else if (mode == 5) {
		r = max(a, b);
	} else if (mode == 6) {
		r = min(a, b);
	} else if (mode == 7) {
		r = abs(a - b);
	} else if (mode == 8) {
		r = a < 0.5 ? 2.0 * a * b : 1.0 - 2.0 * (1.0 - a) * (1.0 - b);
	} else {
		r = b;
	}
	return mix(a, r, amount);
}

// mode: 0 덮어쓰기(B 알파 기준), 1 add, 2 multiply, 3 screen, 4 mix
vec4 vfx_color_blend(vec4 a, vec4 b, int mode, float amount) {
	if (mode == 1) {
		return vec4(a.rgb + b.rgb * b.a * amount, max(a.a, b.a * amount));
	} else if (mode == 2) {
		return mix(a, a * b, amount);
	} else if (mode == 3) {
		return mix(a, vec4(1.0 - (1.0 - a.rgb) * (1.0 - b.rgb), max(a.a, b.a)), amount);
	} else if (mode == 4) {
		return mix(a, b, amount);
	}
	float ba = b.a * amount;
	float oa = ba + a.a * (1.0 - ba);
	vec3 rgb = (b.rgb * ba + a.rgb * a.a * (1.0 - ba)) / max(oa, 1e-5);
	return vec4(rgb, oa);
}

float vfx_math(float a, float b, int op) {
	if (op == 0) return a + b;
	if (op == 1) return a - b;
	if (op == 2) return a * b;
	if (op == 3) return a / (abs(b) < 1e-6 ? 1e-6 : b);
	if (op == 4) return pow(max(a, 0.0), b);
	if (op == 5) return min(a, b);
	if (op == 6) return max(a, b);
	if (op == 7) return 1.0 - a;
	if (op == 8) return abs(a);
	if (op == 9) return 0.5 + 0.5 * sin(a * TAU);
	if (op == 10) return fract(a);
	if (op == 11) return mod(a, max(b, 1e-5));
	return a;
}
