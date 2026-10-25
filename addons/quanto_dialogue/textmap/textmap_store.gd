class_name TextMapStore
extends RefCounted
## Shared, lazy, refcounted cache of TextMaps. One store per game (or per editor).
##
##   var store := TextMapStore.new(registry, "fr")
##   store.acquire("chapter1")            # loads chapter1 for "fr" and the source locale
##   store.lookup("chapter1", "ID_1")     # "fr" text, else source text, else null
##   store.release("chapter1")            # last release drops it from memory
##
## Locale fallback is locale -> source locale. An empty string in a NON-source locale
## means "untranslated" and falls through. Maps are never searched implicitly: a lookup
## only ever consults the map you name.
##
## provide() injects a live in-memory map (the editor's unsaved working map). Provided
## maps win over files, are never unloaded, and see edits immediately.

signal locale_changed(locale: String)
signal registry_changed

enum MissingText { REF, EMPTY }
enum MapState { OK, NO_REGISTRY, UNBOUND }

static var _shared: TextMapStore

## What a missing entry resolves to. REF shows the id on screen (default), EMPTY shows nothing.
var missing_text := MissingText.REF

var registry: QuantoDialogueRegistry
var locale: String

var _refs: Dictionary = {}      ## map_id -> int
var _cache: Dictionary = {}     ## map_id -> { locale -> TextMap or null (unreadable) }
var _provided: Dictionary = {}  ## map_id -> { locale -> TextMap }
var _warned: Dictionary = {}


## The game-wide store, created on first use from TextMapLocator.load_registry().
## Use set_shared() to replace it.
static func shared() -> TextMapStore:
	if _shared == null:
		_shared = TextMapStore.new(QuantoDialogueLocator.load_registry())
	return _shared


static func set_shared(store: TextMapStore) -> void:
	_shared = store


func _init(p_registry: QuantoDialogueRegistry, p_locale := "") -> void:
	registry = p_registry
	locale = p_locale if not p_locale.is_empty() else p_registry.source_locale


func set_locale(new_locale: String) -> void:
	if new_locale == locale:
		return
	locale = new_locale
	# Re-fetch for the new locale now, so the hitch happens here and not mid-dialogue.
	for map_id: String in _refs:
		get_map(map_id, locale)
	locale_changed.emit(locale)


# --- lifetime -----------------------------------------------------------------
## Always counts the reference, even if the map is unknown right now, so a resolver
## created before the TextMap was found starts working after set_registry().
## Returns false if the map is currently unknown.
func acquire(map_id: String, _preload := true) -> bool:
	_refs[map_id] = int(_refs.get(map_id, 0)) + 1
	var known := registry.has_map(map_id) or _provided.has(map_id)
	if not known:
		warn_once("unknown:" + map_id, "TextMapStore: unknown map '%s'" % map_id)
	elif _preload:
		get_map(map_id, locale)
		get_map(map_id, registry.source_locale)
	return known


func release(map_id: String) -> void:
	if not _refs.has(map_id):
		return
	_refs[map_id] -= 1
	if _refs[map_id] <= 0:
		_refs.erase(map_id)
		_cache.erase(map_id)


## Drop cached files for a map (e.g. after it changed on disk). Reloads on next use.
func invalidate(map_id: String) -> void:
	_cache.erase(map_id)


## Forget everything held in memory for a map: its provided (working) copy and its
## cached files. References stay counted, so resolvers keep working and re-read it.
func forget_map(map_id: String) -> void:
	_provided.erase(map_id)
	_cache.erase(map_id)


func loaded_map_ids() -> PackedStringArray:
	return PackedStringArray(_refs.keys())


# --- swapping -----------------------------------------------------------------
## Replaces the registry. Held maps stay held and are re-opened from the new one, so
## existing resolvers keep working. Provided (in-memory) maps are untouched.
func set_registry(new_registry: QuantoDialogueRegistry) -> void:
	var old_source := registry.source_locale
	var old_locale := locale
	registry = new_registry
	if locale == old_source:
		locale = registry.source_locale
	_cache.clear()
	_warned.clear()
	for map_id: String in _refs:
		if registry.has_map(map_id) or _provided.has(map_id):
			get_map(map_id, locale)
			get_map(map_id, registry.source_locale)
		else:
			warn_once("unknown:" + map_id, "TextMapStore: unknown map '%s'" % map_id)
	registry_changed.emit()
	if locale != old_locale:
		locale_changed.emit(locale)


## Re-reads the registry file and every map file from disk.
func reload() -> void:
	set_registry(QuantoDialogueRegistry.load_file(registry.path))


func clear_provided() -> void:
	_provided.clear()


# --- state --------------------------------------------------------------------
func map_state(map_id: String) -> MapState:
	if _provided.has(map_id):
		return MapState.OK
	if not registry.is_usable():
		return MapState.NO_REGISTRY
	if not registry.has_map(map_id):
		return MapState.UNBOUND
	return MapState.OK


## True if the source-locale file exists on disk. False is normal for a map that has
## never been saved.
func has_file(map_id: String) -> bool:
	var file := registry.path_for(map_id, registry.source_locale)
	return not file.is_empty() and FileAccess.file_exists(file)


## What to show for a reference that could not be resolved.
func missing_ref(ref: String) -> String:
	return ref if missing_text == MissingText.REF else ""


# --- provided (in-memory) maps ------------------------------------------------
func provide(map: TextMap) -> void:
	if not _provided.has(map.map_id):
		_provided[map.map_id] = {}
	_provided[map.map_id][map.locale] = map


func unprovide(map_id: String, for_locale := "") -> void:
	if for_locale.is_empty():
		_provided.erase(map_id)
	elif _provided.has(map_id):
		_provided[map_id].erase(for_locale)


# --- lookup -------------------------------------------------------------------
## String, or null if the entry exists in no usable locale (or the map isn't acquired).
func lookup(map_id: String, id: String) -> Variant:
	if not _refs.has(map_id) and not _provided.has(map_id):
		return null
	var source := registry.source_locale
	var order: Array = [locale, source] if locale != source else [source]
	for loc: String in order:
		var map := get_map(map_id, loc)
		if map == null or not map.has(id):
			continue
		var text := map.get_text(id)
		if text.is_empty() and loc != source:
			continue  # untranslated placeholder
		return text
	return null


## Provided map first, then the cache, then disk. null = unknown or unreadable.
func get_map(map_id: String, for_locale: String) -> TextMap:
	if _provided.has(map_id) and _provided[map_id].has(for_locale):
		return _provided[map_id][for_locale]
	var per_locale: Dictionary = _cache.get(map_id, {})
	if per_locale.has(for_locale):
		return per_locale[for_locale]  # may be a cached failure (null)
	var map := registry.open_map(map_id, for_locale)
	per_locale[for_locale] = map
	_cache[map_id] = per_locale
	return map


func warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
