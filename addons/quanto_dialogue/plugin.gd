@tool
extends EditorPlugin

const DIALOGUE_EDITOR_SCENE = preload("res://addons/quanto_dialogue/editor/dialogue_editor.tscn")
const ACTION_PREFIX := "quanto_dialogue_"
var editor_ui

func _register_actions() -> void:
	var actions := QuantoShortcutActions.defaults()
	var added := 0
	for action: String in actions:
		var setting := "input/" + action
		if not ProjectSettings.has_setting(setting):
			var value := {"deadzone": 0.5, "events": actions[action]}
			ProjectSettings.set_setting(setting, value)
			ProjectSettings.set_initial_value(setting, value)
			added += 1
	QuantoShortcutActions.ensure_in_input_map()
	if added > 0:
		ProjectSettings.save()


func _enable_plugin() -> void:
	_register_actions()


func _disable_plugin() -> void:
	for action: String in QuantoShortcutActions.defaults():
		ProjectSettings.clear("input/" + action)
	ProjectSettings.save()


func _enter_tree() -> void:
	_register_actions()
	editor_ui = DIALOGUE_EDITOR_SCENE.instantiate()
	#EditorInterface.get_editor_main_screen().add_child(editor_ui)
	_make_visible(false)


func _exit_tree() -> void:
	if editor_ui:
		editor_ui.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if editor_ui:
		editor_ui.visible = visible

#
#func _get_plugin_name() -> String:
	#return "Dialogue"
#
#
#func _get_plugin_icon() -> Texture2D:
	#return EditorInterface.get_editor_theme().get_icon("Script", "EditorIcons")
