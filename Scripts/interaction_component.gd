class_name PlayerInteractor
extends Area3D
## Component: add as a child of Player, with a CollisionShape3D for the reach range.
## Detects Interactable areas, tells the InteractionManager about them, and freezes
## the player's input while an interaction (dialogue etc.) is running.
##
## Layers: put Interactables on a layer (e.g. 4) and set this Area3D's collision mask to it.

@export var player: Player          # leave empty to use the parent
@export var freeze_player := true   # lock movement input during interactions


func _ready() -> void:
	if player == null:
		player = get_parent() as Player
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	InteractionManager.interaction_started.connect(_on_interaction_started)
	InteractionManager.interaction_finished.connect(_on_interaction_finished)


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable:
		InteractionManager.register(area, player)


func _on_area_exited(area: Area3D) -> void:
	if area is Interactable:
		InteractionManager.unregister(area)


func _on_interaction_started(_interactable: Interactable) -> void:
	if freeze_player and player:
		player.input_locked = true


func _on_interaction_finished(_interactable: Interactable) -> void:
	if player:
		player.input_locked = false
