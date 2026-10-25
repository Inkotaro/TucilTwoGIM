@tool
class_name BlockRegistry
extends RefCounted
## The ONLY place that lists event types. To add a new type:
##   1. write a script extending DialogueBlock
##   2. add one line to PATHS
##   3. add a `match` arm in DialogueRunner
## Paths are load()ed at runtime to avoid cyclic preloads.

const PATHS := {
	DialogueEvent.Type.LINE: "res://addons/quanto_dialogue/editor/blocks/line_block.gd",
	DialogueEvent.Type.CHOICE: "res://addons/quanto_dialogue/editor/blocks/choice_block.gd",
	DialogueEvent.Type.EVENT: "res://addons/quanto_dialogue/editor/blocks/game_event_block.gd",
	DialogueEvent.Type.LABEL: "res://addons/quanto_dialogue/editor/blocks/label_block.gd",
	DialogueEvent.Type.JUMP: "res://addons/quanto_dialogue/editor/blocks/jump_block.gd",
	DialogueEvent.Type.CALL: "res://addons/quanto_dialogue/editor/blocks/call_block.gd",
	DialogueEvent.Type.END: "res://addons/quanto_dialogue/editor/blocks/end_block.gd",
}


static func types() -> Array[DialogueEvent.Type]:
	var out: Array[DialogueEvent.Type] = []
	for k in PATHS.keys():
		out.append(k)
	return out


static func label(type: DialogueEvent.Type) -> String:
	return DialogueEvent.get_type_name(type)


static func create(type: DialogueEvent.Type) -> DialogueBlock:
	if not PATHS.has(type):
		push_warning("BlockRegistry: unknown block type '%s'" % type)
		return null
	return load(PATHS[type]).new() as DialogueBlock
