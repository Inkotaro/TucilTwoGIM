class_name TimelineTextResolver
extends TextResolver
## Resolves references for ONE timeline: its own map plus the maps it explicitly imports.
## Anything else is refused, so ids can never silently resolve against the wrong map.
##
##   var resolver := TimelineTextResolver.new(store, "chapter1", ["common"])
##   resolver.resolve("TIMELINE_INTRO_3")   # chapter1
##   resolver.resolve("common:OK")          # imported
##   resolver.resolve("other:X")            # refused -> returns "other:X", warns once
##   resolver.release()                     # also runs automatically when freed
##
## Missing ids return the reference itself (and warn once) rather than blank text.

var map_id: String
var imports: PackedStringArray = []

var _store: TextMapStore
var _held: PackedStringArray = []


func _init(store: TextMapStore, p_map_id: String, p_imports := PackedStringArray()) -> void:
	_store = store
	map_id = p_map_id
	_hold(p_map_id)
	for imp in p_imports:
		if imp != p_map_id and not imports.has(imp):
			imports.append(imp)
			_hold(imp)


func resolve(ref: String) -> String:
	if ref.is_empty():
		return ""
	var parts := parse_ref(ref)
	var target := parts[0] if not parts[0].is_empty() else map_id
	if target != map_id and not imports.has(target):
		_store.warn_once("import:%s>%s" % [map_id, target],
				"TimelineTextResolver: '%s' does not import map '%s' (ref '%s')" % [map_id, target, ref])
		return _store.missing_ref(ref)
	var text: Variant = _store.lookup(target, parts[1])
	if not text is String:
		_store.warn_once("missing:%s:%s" % [target, parts[1]],
				"TimelineTextResolver: no text for '%s' (locale '%s')" % [ref, _store.locale])
		return _store.missing_ref(ref)
	return text


## Safe to call more than once.
func release() -> void:
	for id in _held:
		_store.release(id)
	_held.clear()


func _hold(id: String) -> void:
	_store.acquire(id)
	_held.append(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print_stack()
		print("release: store valid=", is_instance_valid(_store), " held=", _held)
		
		for id in _held:
			_store.release(id)
		_held.clear()
