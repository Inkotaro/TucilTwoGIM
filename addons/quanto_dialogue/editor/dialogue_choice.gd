class_name DialogueChoice
extends Resource

## Reference into the timeline's text map ("ID" or "map_id:ID"). Never raw text.
@export var text_id: String = ""
@export var events: Array[DialogueEvent] = []
