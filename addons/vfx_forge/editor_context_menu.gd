## 파일시스템 독 우클릭 메뉴: 레시피 또는 VFX Forge 로 만든 PNG 를 VFX Forge 에서 연다.
@tool
extends EditorContextMenuPlugin

var plugin: EditorPlugin


func _popup_menu(paths: PackedStringArray) -> void:
	if paths.size() != 1:
		return
	var p := paths[0]
	if p.ends_with(".vfx.json") or p.get_extension().to_lower() == "png":
		var icon := EditorInterface.get_editor_theme().get_icon("GPUParticles2D", "EditorIcons")
		add_context_menu_item("VFX Forge 에서 열기", _open, icon)


func _open(paths: Array) -> void:
	if plugin and paths.size() == 1:
		plugin.open_path(paths[0])
