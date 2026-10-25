class_name DialogueEvent
extends Resource

enum Type { NONE, LINE, CHOICE, LABEL, JUMP, CALL, RETURN, END, EVENT }
const TYPE_NAMES := {
	Type.NONE: "none",
	Type.LINE: "line",
	Type.CHOICE: "choice",
	Type.LABEL: "label",
	Type.JUMP: "jump",
	Type.CALL: "call",
	Type.RETURN: "return",
	Type.END: "end",
	Type.EVENT: "event"
}

@export var type: Type = Type.NONE
@export var speaker: String = ""
## Reference into the timeline's text map ("ID" or "map_id:ID"). Never raw text.
@export var text_id: String = ""
@export var key: String = ""
@export var value: String = ""
@export var options: Array[DialogueChoice] = []
@export var events: Array[DialogueEvent] = []


func _init(p_type: Type = Type.NONE) -> void:
	type = p_type


## Get the string version of the current type
static func get_type_name(_type: DialogueEvent.Type) -> String:
	return TYPE_NAMES.get(_type, "event")


## The Type for a serialized name, or -1 if the name is unknown.
static func type_from_name(type_name: String) -> int:
	for t in TYPE_NAMES:
		if TYPE_NAMES[t] == type_name:
			return t
	return -1


## All user-visible text of this event, including nested options and events.
## Without a resolver the raw text ids are used, so the result is still searchable by id.
func get_search_text(resolver: TextResolver = null) -> String:
	var parts := PackedStringArray()
	for s: String in [speaker, key, value, _resolve(text_id, resolver)]:
		if not s.is_empty():
			parts.append(s)
	for o in options:
		if o == null:
			continue
		var t := _resolve(o.text_id, resolver)
		if not t.is_empty():
			parts.append(t)
		for e in o.events:
			if e != null:
				parts.append(e.get_search_text(resolver))
	for e in events:
		if e != null:
			parts.append(e.get_search_text(resolver))
	return "\n".join(parts)


static func _resolve(ref: String, resolver: TextResolver) -> String:
	if ref.is_empty() or resolver == null:
		return ref
	return resolver.resolve(ref)
