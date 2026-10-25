@tool
class_name TimelinePreview
extends RefCounted

signal finished

var _runner: DialogueRunner
var _tab_container: TabContainer


func _init(runner: DialogueRunner, tab_container: TabContainer) -> void:
	_runner = runner
	_tab_container = tab_container


func run(resource: DialogueDataResource, resolver: TextResolver) -> void:
	if Engine.is_editor_hint():
		_run_in_window(resource, resolver)
	else:
		_run_embedded(resource, resolver)


func _run_in_window(resource: DialogueDataResource, resolver: TextResolver) -> void:
	var scene_path := _runner.scene_file_path
	if scene_path.is_empty():
		push_error("TimelinePreview: DialogueRunner isn't an instanced scene.")
		return
	var instance := (load(scene_path) as PackedScene).instantiate() as DialogueRunner

	var window := Window.new()
	window.title = "Dialogue Preview"
	window.size = Vector2i(800, 450)
	window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	instance.visible = true
	window.add_child(instance)

	instance.timeline_finished.connect(_on_window_finished.bind(window))
	window.close_requested.connect(window.queue_free)
	EditorInterface.get_base_control().add_child(window)
	window.popup()
	instance.start(resource, resolver)


func _run_embedded(resource: DialogueDataResource, resolver: TextResolver) -> void:
	if not _runner.timeline_finished.is_connected(_on_embedded_finished):
		_runner.timeline_finished.connect(_on_embedded_finished)
	_tab_container.current_tab = 1
	_runner.grab_focus()
	_runner.start(resource, resolver)


func _on_window_finished(window: Window) -> void:
	if is_instance_valid(window):
		window.queue_free()
	finished.emit()


func _on_embedded_finished() -> void:
	_tab_container.current_tab = 0
	finished.emit()
