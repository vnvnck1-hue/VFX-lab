## 횃불 프리팹: 불꽃(VisualShader) + 불티/연기(GPUParticles2D) + 깜빡이는 PointLight2D.
## 인스턴스마다 불꽃 time_offset 과 깜빡임 시드를 달리해 여러 개 놓아도 똑같이 움직이지 않게 한다.
extends Node2D

@export var flicker_speed := 9.0
@export_range(0.0, 1.0) var flicker_strength := 0.25

var _noise := FastNoiseLite.new()
var _t := 0.0
var _base_energy: float
var _base_scale: float

@onready var _flame: CanvasItem = $Flame
@onready var _light: PointLight2D = $Light


func _ready() -> void:
	var seed_value := randi()
	_noise.seed = seed_value
	_noise.frequency = 1.0

	var mat := _flame.material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("time_offset", float(seed_value % 1000) * 0.1)
	_flame.material = mat

	_base_energy = _light.energy
	_base_scale = _light.texture_scale


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := _noise.get_noise_1d(_t)  # -1 ~ 1
	_light.energy = _base_energy * (1.0 + n * flicker_strength)
	_light.texture_scale = _base_scale * (1.0 + n * flicker_strength * 0.3)
