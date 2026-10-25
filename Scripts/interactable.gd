class_name Interactable
extends Area3D
## Add as a child of an NPC (with a CollisionShape3D defining its interaction area).
## The PlayerInteractor on the player detects this area; nothing to configure here
## except putting it on a layer the PlayerInteractor's mask can see.

signal interacted(interactor: Node3D)
signal focused
signal unfocused

@export var prompt_text: String = "Talk"
@export var display_name: String = ""
@export var enabled: bool = true
## Higher priority wins over closer distance.
@export var _priority: int = 0
## If true, the player must be roughly looking toward this object.
@export var require_facing: bool = false
@export_range(-1.0, 1.0, 0.05) var facing_threshold: float = 0.3

var is_focused: bool = false


func _ready() -> void:
	monitoring = false    # the PlayerInteractor does the detecting
	monitorable = true


func _exit_tree() -> void:
	InteractionManager.unregister(self)


func interact(interactor: Node3D) -> void:
	if not enabled:
		return
	interacted.emit(interactor)


func set_focused(value: bool) -> void:
	if is_focused == value:
		return
	is_focused = value
	if value:
		focused.emit()
	else:
		unfocused.emit()
