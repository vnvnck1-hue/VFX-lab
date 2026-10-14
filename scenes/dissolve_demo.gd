## Dissolve 데모: 오브젝트마다 머티리얼을 복제해 위상을 다르게 주고 dissolve_amount 를 왕복시킨다.
## (게임에서는 피격 사망/소환 연출 때 Tween 으로 0→1 한 번만 돌리면 된다.)
extends Node3D

@export var cycle_seconds := 3.0

var _mats: Array[ShaderMaterial] = []
var _t := 0.0

@onready var _targets: Array[MeshInstance3D] = [$Sphere, $Torus, $Capsule]
@onready var _label: Label = $UI/Label


func _ready() -> void:
	var colors := [Color(0.15, 0.55, 0.9), Color(0.85, 0.2, 0.4), Color(0.3, 0.8, 0.35)]
	var edges := [Color(1.0, 0.45, 0.1), Color(0.3, 0.8, 1.0), Color(0.9, 1.0, 0.3)]
	for i in _targets.size():
		var mat := _targets[i].material_override.duplicate() as ShaderMaterial
		mat.set_shader_parameter("base_color", colors[i])
		mat.set_shader_parameter("edge_color", edges[i])
		_targets[i].material_override = mat
		_mats.append(mat)


func _process(delta: float) -> void:
	_t += delta
	for i in _mats.size():
		# 0.5 ~ 1 사이클 차이를 두고 -0.1 ~ 1.05 범위 왕복 (양 끝에서 잠깐 멈추게 clamp)
		var phase := fmod(_t / cycle_seconds + i * 0.33, 2.0)
		var v := phase if phase < 1.0 else 2.0 - phase
		v = clampf(v * 1.3 - 0.15, 0.0, 1.0)
		_mats[i].set_shader_parameter("dissolve_amount", lerpf(-0.1, 1.05, v))
		_targets[i].rotate_y(delta * 0.6)
	_label.text = "Godot Visual Shader — Dissolve\nFPS %d" % Engine.get_frames_per_second()
