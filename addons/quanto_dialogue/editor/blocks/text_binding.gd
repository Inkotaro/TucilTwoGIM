class_name TextBinding
extends RefCounted
## Ties a LineEdit/TextEdit to a text id in the active working map.
## The id field next to it can be edited to relink, and "…" opens a picker.

signal relinked  ## the id changed (not the text)

var text_id := ""
var chip: HBoxContainer  ## put this next to the text widget
var id_edit: LineEdit
var pick_btn: Button

var _w: Control
var _syncing := false
var _picker: TextPicker


func _init(widget: Control) -> void:
	_w = widget
	chip = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)

	id_edit = LineEdit.new()
	id_edit.placeholder_text = "(no id yet)"
	id_edit.custom_minimum_size = Vector2(150, 0)
	id_edit.add_theme_font_size_override("font_size", 11)
	id_edit.tooltip_text = "Text id. Type an existing id to link to it, a new id to create it, or clear it for a fresh own id."
	id_edit.text_submitted.connect(_commit_id)
	id_edit.focus_exited.connect(func(): _commit_id(id_edit.text))
	chip.add_child(id_edit)
	EventList.make_drop_through(id_edit)

	pick_btn = Button.new()
	pick_btn.text = "…"
	pick_btn.flat = true
	pick_btn.tooltip_text = "Pick an existing text id"
	pick_btn.pressed.connect(_open_picker)
	chip.add_child(pick_btn)
	EventList.make_drop_through(pick_btn)

	if widget is LineEdit:
		widget.text_changed.connect(func(t: String): _edited(t))
	else:
		widget.text_changed.connect(func(): _edited(widget.text))
	_refresh_chip()


func is_qualified() -> bool:
	return not TextResolver.parse_ref(text_id)[0].is_empty()


func load_ref(ref: String) -> void:
	_syncing = true
	text_id = ref
	_w.text = DialogueBlock.read_text(ref)
	_w.editable = not (is_qualified() or DialogueBlock.text_locked)
	id_edit.editable = not DialogueBlock.text_locked
	pick_btn.disabled = DialogueBlock.text_locked
	_syncing = false
	_refresh_chip()
	


func _edited(text: String) -> void:
	if _syncing or is_qualified() or DialogueBlock.text_locked:
		return
	if text_id.is_empty():
		if text.is_empty():
			return
		text_id = DialogueBlock.new_text_id()
		if text_id.is_empty():
			return
		_refresh_chip()
	DialogueBlock.write_text(text_id, text)


# --- relinking ----------------------------------------------------------------
func _commit_id(raw: String) -> void:
	if DialogueBlock.text_locked:
		_refresh_chip()
		return
	var new_id := raw.strip_edges()
	if new_id == text_id:
		_refresh_chip()
		return
	if new_id.is_empty():
		_give_own_id()
		return
	if not _ref_ok(new_id):
		push_warning("TextBinding: '%s' is not a valid or importable id" % new_id)
		_refresh_chip()
		return
	_link(new_id)


## Cleared field: detach from a shared id by copying the text under a fresh one.
func _give_own_id() -> void:
	if _w.text.is_empty():
		text_id = ""
		_w.editable = true
		_refresh_chip()
		relinked.emit()
		return
	var fresh := DialogueBlock.new_text_id()
	if fresh.is_empty():
		_refresh_chip()
		return
	DialogueBlock.write_text(fresh, _w.text)
	text_id = fresh
	_w.editable = true
	_refresh_chip()
	relinked.emit()


func _link(ref: String) -> void:
	var parts := TextResolver.parse_ref(ref)
	if parts[0] == DialogueBlock.text_map.map_id:
		ref = parts[1]
		parts = TextResolver.parse_ref(ref)
	if ref == text_id:
		_refresh_chip()
		return
	# Unknown own id: create it, seeded with what is currently typed.
	if parts[0].is_empty() and not DialogueBlock.text_map.has(ref):
		DialogueBlock.write_text(ref, _w.text)
	load_ref(ref)  # shows the linked text
	relinked.emit()


func _ref_ok(ref: String) -> bool:
	var parts := TextResolver.parse_ref(ref)
	if not TextMap.is_valid_id(parts[1]):
		return false
	if parts[0].is_empty() or parts[0] == DialogueBlock.text_map.map_id:
		return true
	# Qualified: must be imported and must already exist (we never create in other maps).
	var r := DialogueBlock.resolver as TimelineTextResolver
	if r == null or not r.imports.has(parts[0]) or DialogueBlock.store == null:
		return false
	return DialogueBlock.store.lookup(parts[0], parts[1]) is String


func _open_picker() -> void:
	if _picker == null:
		_picker = TextPicker.new()
		_picker.picked.connect(_on_picked)
		chip.add_child(_picker)
	_picker.open_at(id_edit)


func _on_picked(ref: String) -> void:
	if _ref_ok(ref):
		_link(ref)


func _refresh_chip() -> void:
	id_edit.text = text_id
	
# --- helpers over event trees --------------------------------------------------
## Unqualified (own-map) ids used by `events`, recursively.
static func collect_ids(events: Array, out: Dictionary) -> void:
	for e: DialogueEvent in events:
		_add(e.text_id, out)
		for o in e.options:
			_add(o.text_id, out)
			collect_ids(o.events, out)
		collect_ids(e.events, out)


static func _add(ref: String, out: Dictionary) -> void:
	if not ref.is_empty() and TextResolver.parse_ref(ref)[0].is_empty():
		out[ref] = true


## In place: text_id -> mapping[text_id] where present.
static func remap_ids(events: Array, mapping: Dictionary) -> void:
	for e: DialogueEvent in events:
		e.text_id = mapping.get(e.text_id, e.text_id)
		for o in e.options:
			o.text_id = mapping.get(o.text_id, o.text_id)
			remap_ids(o.events, mapping)
		remap_ids(e.events, mapping)


static func clone(e: DialogueEvent) -> DialogueEvent:
	var c := DialogueEvent.new(e.type)
	c.speaker = e.speaker
	c.text_id = e.text_id
	c.key = e.key
	c.value = e.value
	for o in e.options:
		var oc := DialogueChoice.new()
		oc.text_id = o.text_id
		for ev in o.events:
			oc.events.append(clone(ev))
		c.options.append(oc)
	for ev in e.events:
		c.events.append(clone(ev))
	return c


## In place: give every own-map id a fresh id holding a copy of its text.
## `texts` (id -> text) overrides what's in the working map (used by the clipboard).
static func refresh_ids(e: DialogueEvent, texts: Dictionary) -> void:
	e.text_id = _fresh(e.text_id, texts)
	for o in e.options:
		o.text_id = _fresh(o.text_id, texts)
		for ev in o.events:
			refresh_ids(ev, texts)
	for ev in e.events:
		refresh_ids(ev, texts)


static func _fresh(ref: String, texts: Dictionary) -> String:
	if ref.is_empty() or not TextResolver.parse_ref(ref)[0].is_empty():
		return ref
	var id := DialogueBlock.new_text_id()
	if id.is_empty():
		return ref
	DialogueBlock.write_text(id, texts.get(ref, DialogueBlock.read_text(ref)))
	return id
