extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Dialogic.start("void")
	Dialogic.connect("timeline_ended", _on_dialogic_timeline_ended)
	pass # Replace with function body.

func _on_dialogic_timeline_ended() -> void:
	get_tree().change_scene_to_packed(load("res://Scenes/rhythm-3d.tscn"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
