class_name TextResolver
extends RefCounted
## Interface: turns a text reference into display text. The interpreter only ever
## sees this class, so the runtime (files) and the editor (unsaved working maps)
## can plug in different implementations.
##
## A reference is "ID" (the timeline's own map) or "map_id:ID" (an imported map).


## Display text for `ref`. Implementations must never return an empty string for a
## missing entry: return `ref` itself so gaps are visible instead of blank.
func resolve(ref: String) -> String:
	return ref


## "common:OK" -> ["common", "OK"],  "OK" -> ["", "OK"]
static func parse_ref(ref: String) -> PackedStringArray:
	var i := ref.find(":")
	if i == -1:
		return PackedStringArray(["", ref])
	return PackedStringArray([ref.substr(0, i), ref.substr(i + 1)])


## Qualified only when `map_id` differs from `own_map_id`, so single-map timelines
## store plain ids on disk.
static func make_ref(map_id: String, id: String, own_map_id: String) -> String:
	return id if map_id == own_map_id or map_id.is_empty() else "%s:%s" % [map_id, id]
