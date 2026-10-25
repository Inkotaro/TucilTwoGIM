extends Node
## Test: loads every timeline in the registry (found by QuantoDialogueLocator) with
## registry.open_timeline() and plays them one after another in a DialogueRunner.
## Press ui_accept to advance.
@onready var player: QuantoDialoguePlayer = %QuantoDialoguePlayer

func _ready() -> void:
	player.timeline_finished.connect(func(id): print("done: ", id))
	player.timeline_failed.connect(func(id, reason): print("FAILED [", id, "] ", reason))
	print("registry: ", QuantoDialogue.registry().path, " ids: ", QuantoDialogue.ids())
	player.queue_finished.connect(func(): print("all done"))
	player.play("gus")                    # one timeline
	# player.play_queue(["intro", "shop"])  # in order
	# player.play_all()                     # everything in the registry, sorted by id
