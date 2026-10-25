extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/platformer-3d.tscn")
	pass # Replace with function body.


func _on_exit_button_pressed() -> void:
	get_tree().quit()
	pass # Replace with function body.

var dialog_editor = preload("res://addons/quanto_dialogue/editor/dialogue_editor.tscn")
func _on_dialog_editor_button_pressed() -> void:
	get_tree().change_scene_to_packed(dialog_editor)
	pass # Replace with function body.
