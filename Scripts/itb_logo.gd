extends Sprite3D
@onready var player: QuantoDialoguePlayer = %QuantoDialoguePlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_interactable_interacted(interactor: Node3D) -> void:
	player.timeline_finished.connect(func(id): InteractionManager.finish_interaction())
	player.play("itb-prophecy")
	pass # Replace with function body.
