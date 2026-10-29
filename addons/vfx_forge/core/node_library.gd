## VFX Forge 노드 정의.
## 노드마다 입력/파라미터/출력과 GLSL 템플릿을 가진다. 컴파일러(compiler.gd)가 템플릿을 채워 셰이더를 만든다.
##
## 템플릿 치환 규칙
##   {이름}   입력 또는 파라미터의 식 (연결되어 있으면 연결된 노드의 출력, 아니면 uniform 이름)
##   {$이름}  이 노드 전용 지역 변수 이름
##   {t}      현재 프레임 시간 (0..1)
## 파라미터 타입: float, int, enum, bool, color, vec2, gradient, bezier
## port = true 인 float/color 파라미터는 왼쪽 포트로 다른 노드 출력을 꽂을 수 있다.
@tool
extends RefCounted

enum { UV, FLOAT, COLOR }

const TYPE_NAMES := ["uv", "float", "color"]
const GLSL_TYPES := ["vec2", "float", "vec4"]
const PORT_COLORS := [Color(0.72, 0.52, 1.0), Color(0.78, 0.78, 0.78), Color(1.0, 0.72, 0.3)]

const CATEGORIES := ["좌표 UV", "모양 Shape", "패턴 Pattern", "시간 Time", "수학 Math", "색 Color", "출력 Output"]

const SOFT := {"name": "softness", "label": "부드러움", "type": "float", "default": 0.004, "min": 0.0, "max": 0.2, "step": 0.001, "port": true}

const NODES := {
	# ================= 좌표 =================
	"uv": {
		"title": "UV", "category": "좌표 UV",
		"desc": "현재 픽셀의 좌표 (0..1, 왼쪽 위가 0)",
		"inputs": [], "params": [],
		"outputs": [{"name": "uv", "type": UV, "expr": "uv"}],
	},
	"transform": {
		"title": "변형 Transform", "category": "좌표 UV",
		"desc": "좌표를 이동/회전/확대한다. 값이 커질수록 내용이 커진다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "offset", "label": "이동", "type": "vec2", "default": [0.0, 0.0], "min": -1.0, "max": 1.0},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "scale", "label": "크기", "type": "float", "default": 1.0, "min": 0.05, "max": 4.0, "step": 0.001, "port": true},
			{"name": "scale_y", "label": "세로 비율", "type": "float", "default": 1.0, "min": 0.05, "max": 4.0, "step": 0.001},
			{"name": "pivot", "label": "기준점", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
		],
		"pre": "vec2 {$p} = vfx_rot({uv} - {pivot} - {offset}, -{rotate}) / max(vec2({scale}, {scale} * {scale_y}), vec2(1e-4));",
		"outputs": [{"name": "uv", "type": UV, "expr": "{$p} + {pivot}"}],
	},
	"tile": {
		"title": "반복 Tile", "category": "좌표 UV",
		"desc": "좌표를 칸으로 나눠 반복한다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "count_x", "label": "가로 개수", "type": "float", "default": 2.0, "min": 1.0, "max": 16.0, "step": 1.0},
			{"name": "count_y", "label": "세로 개수", "type": "float", "default": 2.0, "min": 1.0, "max": 16.0, "step": 1.0},
		],
		"outputs": [{"name": "uv", "type": UV, "expr": "fract({uv} * vec2({count_x}, {count_y}))"}],
	},
	"polar": {
		"title": "극좌표 Polar", "category": "좌표 UV",
		"desc": "직교→극좌표: x = 각도(0..1), y = 중심 거리(가장자리 1). 링/소용돌이 만들 때 쓴다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "mode", "label": "방향", "type": "enum", "default": 0, "options": ["직교 → 극좌표", "극좌표 → 직교"]},
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
		],
		"pre": "vec2 {$d} = {uv} - {center};\nvec2 {$p} = {mode} == 0 ? vec2(fract(atan({$d}.y, {$d}.x) / TAU + 1.0), length({$d}) * 2.0) : {center} + vec2(cos({uv}.x * TAU), sin({uv}.x * TAU)) * {uv}.y * 0.5;",
		"outputs": [{"name": "uv", "type": UV, "expr": "{$p}"}],
	},
	"twirl": {
		"title": "소용돌이 Twirl", "category": "좌표 UV",
		"desc": "중심 가까울수록 더 많이 돌린다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "strength", "label": "세기(바퀴)", "type": "float", "default": 0.3, "min": -2.0, "max": 2.0, "step": 0.001, "port": true},
			{"name": "radius", "label": "반경", "type": "float", "default": 0.5, "min": 0.01, "max": 1.5, "step": 0.001},
		],
		"pre": "vec2 {$d} = {uv} - {center};\nfloat {$k} = clamp(1.0 - length({$d}) / {radius}, 0.0, 1.0);",
		"outputs": [{"name": "uv", "type": UV, "expr": "{center} + vfx_rot({$d}, {strength} * {$k} * {$k})"}],
	},
	"kaleido": {
		"title": "만화경 Kaleidoscope", "category": "좌표 UV",
		"desc": "원을 조각으로 나눠 같은 무늬를 반복한다. 마법진/눈꽃에 쓴다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "segments", "label": "조각 수", "type": "float", "default": 6.0, "min": 1.0, "max": 32.0, "step": 1.0},
			{"name": "mirror", "label": "거울 반사", "type": "bool", "default": true},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
		],
		"pre": "vec2 {$d} = vfx_rot({uv} - {center}, -{rotate});\nfloat {$sec} = TAU / max({segments}, 1.0);\nfloat {$a} = mod(atan({$d}.y, {$d}.x), {$sec});\n{$a} = mix({$a}, abs({$a} - {$sec} * 0.5), {mirror});",
		"outputs": [{"name": "uv", "type": UV, "expr": "{center} + vec2(cos({$a}), sin({$a})) * length({$d})"}],
	},
	"scroll": {
		"title": "흐름 Scroll", "category": "좌표 UV",
		"desc": "시간에 따라 내용을 흘린다. 루프면 속도가 정수(바퀴/루프)로 맞춰져 이음새가 없다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "speed_x", "label": "가로 속도", "type": "float", "default": 0.0, "min": -8.0, "max": 8.0, "step": 1.0},
			{"name": "speed_y", "label": "세로 속도", "type": "float", "default": -1.0, "min": -8.0, "max": 8.0, "step": 1.0},
		],
		"outputs": [{"name": "uv", "type": UV, "expr": "{uv} - vec2(vfx_cyc({speed_x}), vfx_cyc({speed_y})) * {t}"}],
	},
	"warp": {
		"title": "일그러짐 Warp", "category": "좌표 UV",
		"desc": "노이즈 값으로 좌표를 밀어 형태를 일렁이게 한다. Y 를 비우면 X 를 같이 쓴다.",
		"inputs": [{"name": "uv", "type": UV}, {"name": "x", "type": FLOAT, "default": "0.5"}, {"name": "y", "type": FLOAT, "default": "{x}"}],
		"params": [
			{"name": "strength", "label": "세기", "type": "float", "default": 0.1, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "dir", "label": "방향", "type": "enum", "default": 0, "options": ["양방향", "가로만", "세로만"]},
		],
		"pre": "vec2 {$o} = (vec2({x}, {y}) - 0.5) * {strength};\nif ({dir} == 1) {$o}.y = 0.0;\nif ({dir} == 2) {$o}.x = 0.0;",
		"outputs": [{"name": "uv", "type": UV, "expr": "{uv} + {$o}"}],
	},

	# ================= 모양 =================
	"circle": {
		"title": "원 Circle", "category": "모양 Shape",
		"desc": "채운 원. 고리(외곽선만)를 켜면 두께만큼의 고리가 된다 (두께 0 이면 사라짐).",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "radius", "label": "반지름", "type": "float", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "outline", "label": "고리 (외곽선만)", "type": "bool", "default": false},
			{"name": "thickness", "label": "고리 두께", "type": "float", "default": 0.05, "min": 0.0, "max": 0.5, "step": 0.001, "port": true},
			SOFT,
		],
		"pre": "float {$d} = vfx_sd_circle({uv}, {center}, {radius});\n{$d} = {outline} > 0.5 ? abs({$d}) - {thickness} * 0.5 : {$d};",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},
	"polygon": {
		"title": "다각형/별 Polygon", "category": "모양 Shape",
		"desc": "별 정도 0 = 정다각형, 높일수록 뾰족한 별.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "radius", "label": "반지름", "type": "float", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "sides", "label": "꼭짓점", "type": "float", "default": 5.0, "min": 3.0, "max": 24.0, "step": 1.0},
			{"name": "star", "label": "별 정도", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "outline", "label": "외곽선만", "type": "bool", "default": false},
			{"name": "thickness", "label": "외곽선 두께", "type": "float", "default": 0.02, "min": 0.0, "max": 0.3, "step": 0.001, "port": true},
			SOFT,
		],
		"pre": "float {$d} = vfx_sd_star({uv}, {center}, {radius}, {sides}, {star}, {rotate});\n{$d} = {outline} > 0.5 ? abs({$d}) - {thickness} * 0.5 : {$d};",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},
	"rect": {
		"title": "사각형 Rectangle", "category": "모양 Shape",
		"desc": "",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "width", "label": "가로", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "height", "label": "세로", "type": "float", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "round", "label": "모서리", "type": "float", "default": 0.0, "min": 0.0, "max": 0.5, "step": 0.001},
			{"name": "outline", "label": "외곽선만", "type": "bool", "default": false},
			{"name": "thickness", "label": "외곽선 두께", "type": "float", "default": 0.02, "min": 0.0, "max": 0.3, "step": 0.001},
			SOFT,
		],
		"pre": "float {$d} = vfx_sd_box({uv}, {center}, vec2({width}, {height}) * 0.5, {rotate}, min({round}, min({width}, {height}) * 0.5));\n{$d} = {outline} > 0.5 ? abs({$d}) - {thickness} * 0.5 : {$d};",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},
	"line": {
		"title": "선 Line", "category": "모양 Shape",
		"desc": "시작/끝 두께를 다르게 주면 뾰족한 선이 된다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "a", "label": "시작", "type": "vec2", "default": [0.2, 0.5], "min": 0.0, "max": 1.0},
			{"name": "b", "label": "끝", "type": "vec2", "default": [0.8, 0.5], "min": 0.0, "max": 1.0},
			{"name": "width_a", "label": "시작 두께", "type": "float", "default": 0.02, "min": 0.0, "max": 0.3, "step": 0.001, "port": true},
			{"name": "width_b", "label": "끝 두께", "type": "float", "default": 0.02, "min": 0.0, "max": 0.3, "step": 0.001, "port": true},
			SOFT,
		],
		"pre": "float {$d} = vfx_sd_line({uv}, {a}, {b}, {width_a}, {width_b});",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},
	"arc": {
		"title": "호 Arc", "category": "모양 Shape",
		"desc": "원의 일부만 그린다. 시작/길이는 바퀴 단위 (1 = 한 바퀴).",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "radius", "label": "반지름", "type": "float", "default": 0.35, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "thickness", "label": "두께", "type": "float", "default": 0.03, "min": 0.0, "max": 0.5, "step": 0.001, "port": true},
			{"name": "start", "label": "시작", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "length", "label": "길이", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			SOFT,
		],
		"pre": "float {$d} = vfx_sd_arc({uv}, {center}, {radius}, {thickness}, {start}, {length});",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},
	"gradient": {
		"title": "그라데이션 Gradient", "category": "모양 Shape",
		"desc": "0..1 값을 만든다. 그라데이션 맵과 함께 색을 입힌다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "mode", "label": "종류", "type": "enum", "default": 1, "options": ["선형", "방사형", "각도", "다이아몬드"]},
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "angle", "label": "각도(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "scale", "label": "배율", "type": "float", "default": 1.0, "min": 0.05, "max": 8.0, "step": 0.001, "port": true},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "vfx_gradient({uv}, {mode}, {center}, {angle}, {scale})"}],
	},
	"rays": {
		"title": "빛줄기 Rays", "category": "모양 Shape",
		"desc": "중심에서 뻗는 뾰족한 줄기. 임팩트/플레어/별빛에 쓴다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "count", "label": "개수", "type": "float", "default": 12.0, "min": 1.0, "max": 64.0, "step": 1.0},
			{"name": "width", "label": "굵기", "type": "float", "default": 0.03, "min": 0.0, "max": 0.2, "step": 0.001, "port": true},
			{"name": "len_min", "label": "최소 길이", "type": "float", "default": 0.25, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "len_max", "label": "최대 길이", "type": "float", "default": 0.45, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "jitter", "label": "각도 흩어짐", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001},
			SOFT,
			{"name": "seed", "label": "시드", "type": "int", "default": 1, "min": 0, "max": 9999},
		],
		"outputs": [{"name": "mask", "type": FLOAT, "expr": "vfx_rays({uv}, {center}, {count}, {width}, {len_min}, {len_max}, {rotate}, {jitter}, {softness}, {seed})"}],
	},
	"scatter": {
		"title": "파편 Scatter", "category": "모양 Shape",
		"desc": "진행도 0→1 동안 중심에서 바깥으로 튀며 작아지는 파편/불티. 진행도에 시간을 연결한다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "progress", "label": "진행도", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "count", "label": "개수", "type": "float", "default": 16.0, "min": 1.0, "max": 64.0, "step": 1.0},
			{"name": "direction", "label": "방향(바퀴)", "type": "float", "default": 0.75, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "spread", "label": "퍼짐(바퀴)", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "start_radius", "label": "시작 거리", "type": "float", "default": 0.05, "min": 0.0, "max": 0.5, "step": 0.001},
			{"name": "travel", "label": "이동 거리", "type": "float", "default": 0.4, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "size", "label": "크기", "type": "float", "default": 0.02, "min": 0.001, "max": 0.2, "step": 0.001, "port": true},
			{"name": "size_random", "label": "크기 랜덤", "type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "streak", "label": "꼬리 길이", "type": "float", "default": 2.0, "min": 0.0, "max": 10.0, "step": 0.01},
			{"name": "fade", "label": "작아짐", "type": "float", "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01},
			{"name": "seed", "label": "시드", "type": "int", "default": 1, "min": 0, "max": 9999},
		],
		"outputs": [{"name": "mask", "type": FLOAT, "expr": "vfx_scatter({uv}, {center}, {count}, {direction}, {spread}, {start_radius}, {travel}, {size}, {size_random}, {streak}, {progress}, {fade}, {seed})"}],
	},
	"bezier": {
		"title": "베지어 스트로크 Bezier", "category": "모양 Shape",
		"desc": "슬래시/검기. 미리보기에서 점을 끌어 키 포즈를 만들면 사이 프레임은 자동으로 보간된다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "poses", "label": "키 포즈", "type": "bezier", "default": [
				{"t": 0.0, "p": [[0.12, 0.72], [0.22, 0.18], [0.78, 0.18], [0.88, 0.72]], "head": 0.05, "tail": 0.0, "width": 0.07},
				{"t": 0.45, "p": [[0.12, 0.72], [0.22, 0.18], [0.78, 0.18], [0.88, 0.72]], "head": 1.0, "tail": 0.15, "width": 0.07},
				{"t": 1.0, "p": [[0.12, 0.72], [0.22, 0.18], [0.78, 0.18], [0.88, 0.72]], "head": 1.0, "tail": 1.0, "width": 0.0},
			]},
			{"name": "taper", "label": "끝 가늘기", "type": "float", "default": 0.8, "min": 0.05, "max": 4.0, "step": 0.01},
			{"name": "peak", "label": "가장 두꺼운 곳", "type": "float", "default": 0.7, "min": 0.01, "max": 0.99, "step": 0.001},
			{"name": "smooth", "label": "부드러운 보간", "type": "bool", "default": true},
			SOFT,
		],
		"pre": "int {$k} = 0;\nfor (int i = 0; i < {poses}_n - 1; i++) {\n\tif ({t} >= {poses}_t[i + 1]) {\n\t\t{$k} = i + 1;\n\t}\n}\nint {$k2} = min({$k} + 1, {poses}_n - 1);\nfloat {$f} = {$k2} == {$k} ? 0.0 : clamp(({t} - {poses}_t[{$k}]) / max({poses}_t[{$k2}] - {poses}_t[{$k}], 1e-5), 0.0, 1.0);\n{$f} = mix({$f}, {$f} * {$f} * (3.0 - 2.0 * {$f}), {smooth});\nvec4 {$d} = mix({poses}_d[{$k}], {poses}_d[{$k2}], {$f});\nvec4 {$r} = vfx_bezier_stroke({uv}, mix({poses}_p[{$k} * 4], {poses}_p[{$k2} * 4], {$f}), mix({poses}_p[{$k} * 4 + 1], {poses}_p[{$k2} * 4 + 1], {$f}), mix({poses}_p[{$k} * 4 + 2], {poses}_p[{$k2} * 4 + 2], {$f}), mix({poses}_p[{$k} * 4 + 3], {poses}_p[{$k2} * 4 + 3], {$f}), {$d}.x, {$d}.y, {$d}.z, {taper}, {peak}, {softness});",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "{$r}.x"},
			{"name": "along", "type": FLOAT, "expr": "{$r}.y"},
			{"name": "across", "type": FLOAT, "expr": "{$r}.z * 0.5 + 0.5"},
			{"name": "stroke_uv", "type": UV, "expr": "vec2({$r}.y, {$r}.z * 0.5 + 0.5)"},
			{"name": "sdf", "type": FLOAT, "expr": "{$r}.w"},
		],
	},
	"lightning": {
		"title": "번개 Lightning", "category": "모양 Shape",
		"desc": "시작→끝 지그재그 번개와 가지. 깜빡임 횟수만큼 루프 동안 모양이 바뀐다.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "a", "label": "시작", "type": "vec2", "default": [0.5, 0.05], "min": 0.0, "max": 1.0},
			{"name": "b", "label": "끝", "type": "vec2", "default": [0.5, 0.95], "min": 0.0, "max": 1.0},
			{"name": "amplitude", "label": "흔들림", "type": "float", "default": 0.12, "min": 0.0, "max": 0.5, "step": 0.001, "port": true},
			{"name": "frequency", "label": "꺾임 수", "type": "float", "default": 6.0, "min": 1.0, "max": 30.0, "step": 0.01},
			{"name": "width", "label": "굵기", "type": "float", "default": 0.01, "min": 0.0, "max": 0.1, "step": 0.0005, "port": true},
			{"name": "glow", "label": "글로우 폭", "type": "float", "default": 0.04, "min": 0.001, "max": 0.3, "step": 0.001, "port": true},
			{"name": "branches", "label": "가지 수", "type": "float", "default": 2.0, "min": 0.0, "max": 4.0, "step": 1.0},
			{"name": "flicker", "label": "깜빡임 횟수", "type": "float", "default": 4.0, "min": 0.0, "max": 32.0, "step": 1.0},
			{"name": "seed", "label": "시드", "type": "int", "default": 3, "min": 0, "max": 9999},
		],
		"pre": "vec2 {$l} = vfx_lightning({uv}, {a}, {b}, {amplitude}, {frequency}, {width}, {glow}, {branches}, {seed} + int(floor({t} * {flicker})) * 97);",
		"outputs": [
			{"name": "core", "type": FLOAT, "expr": "{$l}.x"},
			{"name": "glow", "type": FLOAT, "expr": "{$l}.y"},
		],
	},
	"rune_ring": {
		"title": "룬 고리 Rune Ring", "category": "모양 Shape",
		"desc": "원을 따라 랜덤 룬 문자를 배치한다. 마법진 글자띠.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "center", "label": "중심", "type": "vec2", "default": [0.5, 0.5], "min": 0.0, "max": 1.0},
			{"name": "radius", "label": "반지름", "type": "float", "default": 0.36, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "size", "label": "글자 높이", "type": "float", "default": 0.06, "min": 0.005, "max": 0.3, "step": 0.001},
			{"name": "count", "label": "글자 수", "type": "float", "default": 24.0, "min": 3.0, "max": 96.0, "step": 1.0},
			{"name": "stroke", "label": "획 두께", "type": "float", "default": 0.006, "min": 0.001, "max": 0.05, "step": 0.0005},
			{"name": "density", "label": "획 밀도", "type": "float", "default": 0.3, "min": 0.05, "max": 1.0, "step": 0.01},
			{"name": "rotate", "label": "회전(바퀴)", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001, "port": true},
			SOFT,
			{"name": "seed", "label": "시드", "type": "int", "default": 7, "min": 0, "max": 9999},
		],
		"pre": "float {$d} = vfx_rune_ring({uv}, {center}, {radius}, {size}, {count}, {stroke}, {density}, {rotate}, {seed});",
		"outputs": [
			{"name": "mask", "type": FLOAT, "expr": "vfx_fill({$d}, {softness})"},
			{"name": "sdf", "type": FLOAT, "expr": "{$d}"},
		],
	},

	# ================= 패턴 =================
	"noise": {
		"title": "노이즈 Noise", "category": "패턴 Pattern",
		"desc": "주기성 노이즈. 타일링/루프 설정에 맞춰 자동으로 이음새 없이 맞춰진다. 변화 = 루프 동안 모양이 변하는 횟수.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "mode", "label": "종류", "type": "enum", "default": 0, "options": ["부드러움", "능선 Ridged", "난류 Billow"]},
			{"name": "scale", "label": "크기(칸 수)", "type": "float", "default": 4.0, "min": 1.0, "max": 32.0, "step": 0.01, "port": true},
			{"name": "stretch_y", "label": "세로 배율", "type": "float", "default": 1.0, "min": 0.1, "max": 8.0, "step": 0.01},
			{"name": "octaves", "label": "디테일", "type": "float", "default": 4.0, "min": 1.0, "max": 8.0, "step": 1.0},
			{"name": "persistence", "label": "거칠기", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "evolve", "label": "변화(회/루프)", "type": "float", "default": 0.0, "min": 0.0, "max": 8.0, "step": 1.0},
			{"name": "wrap_x", "label": "가로 이음새 없음 (극좌표용)", "type": "bool", "default": false},
			{"name": "seed", "label": "시드", "type": "int", "default": 1, "min": 0, "max": 9999},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "vfx_noise({uv}, {scale}, {stretch_y}, {octaves}, {persistence}, {evolve}, {t}, {mode}, {seed}, max(vfx_tiling, vec2({wrap_x}, 0.0)))"}],
	},
	"voronoi": {
		"title": "셀 Voronoi", "category": "패턴 Pattern",
		"desc": "셀 노이즈. 거리 = 셀 중심 거리, 경계 = 셀 사이 선, 셀값 = 셀마다 랜덤.",
		"inputs": [{"name": "uv", "type": UV}],
		"params": [
			{"name": "scale", "label": "크기(칸 수)", "type": "float", "default": 6.0, "min": 1.0, "max": 32.0, "step": 0.01, "port": true},
			{"name": "stretch_y", "label": "세로 배율", "type": "float", "default": 1.0, "min": 0.1, "max": 8.0, "step": 0.01},
			{"name": "jitter", "label": "불규칙", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "anim", "label": "움직임(회/루프)", "type": "float", "default": 0.0, "min": 0.0, "max": 8.0, "step": 1.0},
			{"name": "wrap_x", "label": "가로 이음새 없음 (극좌표용)", "type": "bool", "default": false},
			{"name": "seed", "label": "시드", "type": "int", "default": 1, "min": 0, "max": 9999},
		],
		"pre": "vec3 {$v} = vfx_voronoi({uv}, {scale}, {stretch_y}, {jitter}, {anim}, {t}, {seed}, max(vfx_tiling, vec2({wrap_x}, 0.0)));",
		"outputs": [
			{"name": "dist", "type": FLOAT, "expr": "clamp({$v}.x, 0.0, 1.0)"},
			{"name": "edge", "type": FLOAT, "expr": "clamp({$v}.y, 0.0, 1.0)"},
			{"name": "cell", "type": FLOAT, "expr": "{$v}.z"},
		],
	},

	# ================= 시간 =================
	"time": {
		"title": "시간 Time", "category": "시간 Time",
		"desc": "t = 0→1 (루프면 마지막 프레임이 1 직전), 왕복 = 0→1→0, 파동 = 부드러운 0→1→0",
		"inputs": [], "params": [],
		"outputs": [
			{"name": "t", "type": FLOAT, "expr": "{t}"},
			{"name": "pingpong", "type": FLOAT, "expr": "1.0 - abs(2.0 * {t} - 1.0)"},
			{"name": "wave", "type": FLOAT, "expr": "0.5 - 0.5 * cos({t} * TAU)"},
		],
	},
	"ease": {
		"title": "타이밍 Ease", "category": "시간 Time",
		"desc": "입력(기본 = 시간)을 시작~끝 구간에서 0→1 곡선으로 바꾼다. 요소별 등장 타이밍 조절용.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "{t}"}],
		"params": [
			{"name": "mode", "label": "곡선", "type": "enum", "default": 2, "options": ["선형", "Ease In", "Ease Out", "Ease In-Out", "Smoothstep", "왕복", "펄스(0→1→0)"]},
			{"name": "start", "label": "시작", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "end", "label": "끝", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "power", "label": "강도", "type": "float", "default": 2.0, "min": 0.1, "max": 8.0, "step": 0.01},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "vfx_ease({x}, {start}, {end}, {mode}, {power})"}],
	},

	# ================= 수학 =================
	"value": {
		"title": "값 Value", "category": "수학 Math",
		"desc": "",
		"inputs": [],
		"params": [{"name": "value", "label": "값", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001}],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "{value}"}],
	},
	"math": {
		"title": "연산 Math", "category": "수학 Math",
		"desc": "A 와 B 를 계산. 1-A, |A|, 사인 등은 A 만 쓴다.",
		"inputs": [{"name": "a", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "op", "label": "연산", "type": "enum", "default": 2, "options": ["A + B", "A - B", "A × B", "A ÷ B", "A ^ B", "min", "max", "1 - A", "|A|", "사인 파동", "소수부", "나머지"]},
			{"name": "b", "label": "B", "type": "float", "default": 1.0, "min": -4.0, "max": 4.0, "step": 0.001, "port": true},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "vfx_math({a}, {b}, {op})"}],
	},
	"blend": {
		"title": "섞기 Blend", "category": "수학 Math",
		"desc": "흑백 값 두 개를 섞는다.",
		"inputs": [{"name": "a", "type": FLOAT, "default": "0.0"}, {"name": "b", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "mode", "label": "방식", "type": "enum", "default": 5, "options": ["B로 교체", "더하기", "빼기", "곱하기", "스크린", "밝은 쪽(max)", "어두운 쪽(min)", "차이", "오버레이"]},
			{"name": "amount", "label": "양", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "vfx_blend({a}, {b}, {mode}, {amount})"}],
	},
	"levels": {
		"title": "레벨 Levels", "category": "수학 Math",
		"desc": "입력 범위를 출력 범위로 다시 맞춘다. 감마로 중간 톤 조절.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "in_min", "label": "입력 최소", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "in_max", "label": "입력 최대", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "gamma", "label": "감마", "type": "float", "default": 1.0, "min": 0.1, "max": 5.0, "step": 0.01},
			{"name": "out_min", "label": "출력 최소", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001},
			{"name": "out_max", "label": "출력 최대", "type": "float", "default": 1.0, "min": 0.0, "max": 2.0, "step": 0.001},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "mix({out_min}, {out_max}, pow(clamp(({x} - {in_min}) / max({in_max} - {in_min}, 1e-5), 0.0, 1.0), 1.0 / {gamma}))"}],
	},
	"step": {
		"title": "경계 Step", "category": "수학 Math",
		"desc": "임계값보다 크면 1. 툰 스타일의 딱 떨어지는 외곽을 만든다.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "threshold", "label": "임계값", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "softness", "label": "부드러움", "type": "float", "default": 0.02, "min": 0.0, "max": 0.5, "step": 0.001},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "smoothstep({threshold} - {softness} * 0.5 - 1e-5, {threshold} + {softness} * 0.5, {x})"}],
	},
	"band": {
		"title": "띠 Band", "category": "수학 Math",
		"desc": "중심 값 근처만 1. 외곽선/테두리 띠를 뽑을 때 쓴다.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "center", "label": "중심", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "width", "label": "폭", "type": "float", "default": 0.1, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
			{"name": "softness", "label": "부드러움", "type": "float", "default": 0.02, "min": 0.0, "max": 0.5, "step": 0.001},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "1.0 - smoothstep({width} * 0.5, {width} * 0.5 + {softness} + 1e-5, abs({x} - {center}))"}],
	},
	"posterize": {
		"title": "단계 Posterize", "category": "수학 Math",
		"desc": "값을 몇 단계로 끊는다. 셀 셰이딩 톤.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "0.0"}],
		"params": [{"name": "steps", "label": "단계 수", "type": "float", "default": 4.0, "min": 2.0, "max": 16.0, "step": 1.0}],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "floor(clamp({x}, 0.0, 0.9999) * {steps}) / ({steps} - 1.0)"}],
	},
	"glow": {
		"title": "글로우 Glow", "category": "수학 Math",
		"desc": "도형의 sdf 출력을 받아 바깥으로 퍼지는 빛을 만든다.",
		"inputs": [{"name": "sdf", "type": FLOAT, "default": "1.0"}],
		"params": [
			{"name": "radius", "label": "퍼짐", "type": "float", "default": 0.05, "min": 0.001, "max": 0.5, "step": 0.001, "port": true},
			{"name": "intensity", "label": "세기", "type": "float", "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.001, "port": true},
		],
		"outputs": [{"name": "value", "type": FLOAT, "expr": "exp(-max({sdf}, 0.0) / {radius}) * {intensity}"}],
	},

	# ================= 색 =================
	"color": {
		"title": "색 Color", "category": "색 Color",
		"desc": "",
		"inputs": [],
		"params": [{"name": "color", "label": "색", "type": "color", "default": "#ffffffff"}],
		"outputs": [{"name": "color", "type": COLOR, "expr": "{color}"}],
	},
	"colorize": {
		"title": "색 입히기 Colorize", "category": "색 Color",
		"desc": "흑백 마스크에 색을 입힌다. 알파 = 마스크.",
		"inputs": [{"name": "mask", "type": FLOAT, "default": "1.0"}],
		"params": [
			{"name": "color", "label": "색", "type": "color", "default": "#ffffffff", "port": true},
			{"name": "intensity", "label": "밝기", "type": "float", "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.001},
		],
		"outputs": [{"name": "color", "type": COLOR, "expr": "vec4({color}.rgb * {intensity}, {color}.a * clamp({mask}, 0.0, 1.0))"}],
	},
	"gradient_map": {
		"title": "그라데이션 맵 Gradient Map", "category": "색 Color",
		"desc": "0..1 값을 색 띠로 바꾼다. 스타일라이즈드 이펙트의 핵심 노드.",
		"inputs": [{"name": "x", "type": FLOAT, "default": "0.0"}],
		"params": [
			{"name": "gradient", "label": "색 띠", "type": "gradient", "default": [[0.0, "#00000000"], [0.35, "#ff4a1cff"], [0.7, "#ffb84aff"], [1.0, "#fff6d8ff"]]},
			{"name": "alpha_by_input", "label": "입력으로 알파 곱", "type": "bool", "default": false},
		],
		"pre": "vec4 {$c} = texture({gradient}, vec2(clamp({x}, 0.0, 1.0), 0.5));\n{$c}.a *= mix(1.0, clamp({x}, 0.0, 1.0), {alpha_by_input});",
		"outputs": [{"name": "color", "type": COLOR, "expr": "{$c}"}],
	},
	"color_blend": {
		"title": "색 섞기 Color Blend", "category": "색 Color",
		"desc": "색 A 위에 B 를 섞는다. 마스크로 섞을 영역을 정할 수 있다.",
		"inputs": [{"name": "a", "type": COLOR, "default": "vec4(0.0)"}, {"name": "b", "type": COLOR, "default": "vec4(0.0)"}, {"name": "mask", "type": FLOAT, "default": "1.0"}],
		"params": [
			{"name": "mode", "label": "방식", "type": "enum", "default": 0, "options": ["위에 덮기", "더하기(Add)", "곱하기", "스크린", "섞기(Mix)"]},
			{"name": "amount", "label": "양", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
		],
		"outputs": [{"name": "color", "type": COLOR, "expr": "vfx_color_blend({a}, {b}, {mode}, {amount} * clamp({mask}, 0.0, 1.0))"}],
	},
	"set_alpha": {
		"title": "알파 Set Alpha", "category": "색 Color",
		"desc": "색의 알파를 마스크로 곱하거나 바꾼다.",
		"inputs": [{"name": "color", "type": COLOR, "default": "vec4(1.0)"}, {"name": "alpha", "type": FLOAT, "default": "1.0"}],
		"params": [{"name": "mode", "label": "방식", "type": "enum", "default": 0, "options": ["곱하기", "바꾸기"]}],
		"outputs": [{"name": "color", "type": COLOR, "expr": "vec4({color}.rgb, {mode} == 0 ? {color}.a * {alpha} : clamp({alpha}, 0.0, 1.0))"}],
	},
	"color_adjust": {
		"title": "색 보정 Adjust", "category": "색 Color",
		"desc": "",
		"inputs": [{"name": "color", "type": COLOR, "default": "vec4(1.0)"}],
		"params": [
			{"name": "brightness", "label": "밝기", "type": "float", "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.001, "port": true},
			{"name": "saturation", "label": "채도", "type": "float", "default": 1.0, "min": 0.0, "max": 2.0, "step": 0.001},
			{"name": "hue", "label": "색조 회전", "type": "float", "default": 0.0, "min": -0.5, "max": 0.5, "step": 0.001},
			{"name": "opacity", "label": "불투명도", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.001, "port": true},
		],
		"pre": "vec3 {$c} = {color}.rgb;\nfloat {$l} = dot({$c}, vec3(0.299, 0.587, 0.114));\n{$c} = mix(vec3({$l}), {$c}, {saturation});\nvec3 {$k} = vec3(0.57735);\nfloat {$h} = {hue} * TAU;\n{$c} = {$c} * cos({$h}) + cross({$k}, {$c}) * sin({$h}) + {$k} * dot({$k}, {$c}) * (1.0 - cos({$h}));",
		"outputs": [{"name": "color", "type": COLOR, "expr": "vec4(max({$c}, vec3(0.0)) * {brightness}, {color}.a * {opacity})"}],
	},

	# ================= 출력 =================
	"output": {
		"title": "출력 Output", "category": "출력 Output",
		"desc": "내보낼 최종 이미지. RGBA = 일반 알파, 프리멀티 = Add 블렌드용, 흑백 마스크 = 셰이더 마스크용. 가장자리 페이드는 이미지 테두리에서 알파를 0 으로 줄여 글로우가 네모나게 잘리는 것을 막는다 (타일링 축은 제외).",
		"inputs": [{"name": "color", "type": COLOR, "default": "vec4(0.0)"}],
		"params": [
			{"name": "mode", "label": "형식", "type": "enum", "default": 0, "options": ["RGBA", "프리멀티 알파", "흑백 마스크", "알파 마스크(흰색)"]},
			{"name": "edge_fade", "label": "가장자리 페이드", "type": "float", "default": 0.05, "min": 0.0, "max": 0.5, "step": 0.001},
		],
		"pre": "vec4 {$c} = clamp({color}, 0.0, 1.0);\nvec2 {$e} = mix(min(uv, 1.0 - uv), vec2(1.0), vfx_tiling);\n{$c}.a *= smoothstep(0.0, max({edge_fade}, 1e-5), min({$e}.x, {$e}.y));\nif ({mode} == 1) {$c} = vec4({$c}.rgb * {$c}.a, {$c}.a);\nif ({mode} == 2) {$c} = vec4(vec3(vfx_lum({$c})), 1.0);\nif ({mode} == 3) {$c} = vec4(1.0, 1.0, 1.0, vfx_lum(vec4({$c}.rgb, 1.0)) * {$c}.a);",
		"outputs": [{"name": "color", "type": COLOR, "expr": "{$c}"}],
	},
}

const MAX_BEZIER_KEYS := 8


static func get_def(type: String) -> Dictionary:
	return NODES.get(type, {})


static func find_param(def: Dictionary, name: String) -> Dictionary:
	for p in def.get("params", []):
		if p.name == name:
			return p
	return {}


static func find_input(def: Dictionary, name: String) -> Dictionary:
	for p in def.get("inputs", []):
		if p.name == name:
			return p
	return {}


static func output_index(def: Dictionary, name: String) -> int:
	var outs: Array = def.get("outputs", [])
	for i in outs.size():
		if outs[i].name == name:
			return i
	return -1


## 입력 포트 이름의 타입 (일반 입력 또는 port 가 켜진 파라미터)
static func input_type(def: Dictionary, name: String) -> int:
	var inp := find_input(def, name)
	if not inp.is_empty():
		return inp.type
	var p := find_param(def, name)
	if p.get("port", false):
		return COLOR if p.type == "color" else FLOAT
	return -1


## 카테고리별 노드 타입 목록 (메뉴용)
static func types_in_category(category: String) -> Array:
	var out := []
	for k in NODES:
		if NODES[k].category == category:
			out.append(k)
	return out
