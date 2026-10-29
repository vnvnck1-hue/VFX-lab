## VFX Forge 에디터 플러그인: 2D/3D/Script 옆에 'VFX Forge' 메인 화면 탭을 추가한다.
@tool
extends EditorPlugin

const PANEL := preload("res://addons/vfx_forge/ui/forge_panel.gd")
const ContextMenu := preload("res://addons/vfx_forge/editor_context_menu.gd")

var panel: VfxForgePanel
var context_menu: EditorContextMenuPlugin


func _enter_tree() -> void:
	panel = PANEL.new()
	panel.name = "VfxForge"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.exported.connect(_on_exported)
	_make_visible(false)
	context_menu = ContextMenu.new()
	context_menu.plugin = self
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, context_menu)


func _exit_tree() -> void:
	remove_context_menu_plugin(context_menu)
	if panel:
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel:
		panel.visible = visible


func _get_plugin_name() -> String:
	return "VFX Forge"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GPUParticles2D", "EditorIcons")


## 파일시스템 독에서 레시피/내보낸 PNG 를 열 때
func open_path(path: String) -> void:
	EditorInterface.set_main_screen_editor("VFX Forge")
	if path.ends_with(".vfx.json"):
		panel.open_recipe(path)
	else:
		panel.open_for_texture(path)


func _on_exported(result: Dictionary) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	# 이미 임포트된 PNG 는 새 임포트 설정으로 다시 임포트하고, 새 파일은 스캔으로 잡는다
	var known := PackedStringArray()
	for f in result.get("files", []):
		if str(f).ends_with(".png") and fs.get_file_type(f) != "":
			known.append(f)
	fs.scan()
	if not known.is_empty():
		await fs.filesystem_changed
		fs.reimport_files(known)
