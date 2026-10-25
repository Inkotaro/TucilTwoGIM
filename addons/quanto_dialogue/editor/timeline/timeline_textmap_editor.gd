@tool
class_name TimelineTextMapEditor
extends AcceptDialog

signal closed

var _session: TimelineTextSession
var _map_pick := OptionButton.new()
var _loc_pick := OptionButton.new()
var _new_loc := LineEdit.new()
var _filter := LineEdit.new()
var _new_id := LineEdit.new()
var _tree := Tree.new()
var _source: TextMap  # working map of the source locale (live, shared with the editor)
var _map: TextMap     # map being edited (== _source when editing the source locale)


func _init() -> void:
	title = "Text Editor"
	ok_button_text = "Close"
	min_size = Vector2i(860, 540)
	add_button("Save", false, "save")
	custom_action.connect(func(a: StringName): if a == &"save": _save())
	visibility_changed.connect(func(): if not visible: closed.emit())

	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	top.add_child(_label("Map"))
	top.add_child(_map_pick)
	top.add_child(_label("Locale"))
	top.add_child(_loc_pick)
	_new_loc.placeholder_text = "new locale (fr)"
	top.add_child(_new_loc)
	top.add_child(_button("Add locale", _add_locale))
	_filter.placeholder_text = "filter..."
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_filter)

	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tree)

	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_new_id.placeholder_text = "new id (source locale only)"
	_new_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_new_id)
	bottom.add_child(_button("Add entry", _add_id))
	bottom.add_child(_button("Delete selected", _delete_selected))

	_map_pick.item_selected.connect(func(_i): _load_map())
	_loc_pick.item_selected.connect(func(_i): _load_locale())
	_filter.text_changed.connect(func(_t): _fill())
	_tree.item_edited.connect(_on_edited)


func open(session: TimelineTextSession, map_id: String) -> void:
	_session = session
	_map_pick.clear()
	var ids := session.registry.map_ids()
	for id in ids:
		_map_pick.add_item(id)
	if ids.is_empty():
		push_warning("TimelineTextMapEditor: the registry has no maps")
		return
	_map_pick.select(maxi(ids.find(map_id), 0))
	_load_map()
	popup_centered()


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _map_id() -> String:
	return _map_pick.get_item_text(_map_pick.selected)


func _load_map() -> void:
	_autosave_translation()
	_source = _session.working_map(_map_id())
	var src_locale := _session.registry.source_locale
	_loc_pick.clear()
	_loc_pick.add_item(src_locale)
	for loc in _locales_on_disk(_map_id()):
		if loc != src_locale:
			_loc_pick.add_item(loc)
	_loc_pick.select(0)
	_load_locale()


func _load_locale() -> void:
	_autosave_translation()
	var loc := _loc_pick.get_item_text(_loc_pick.selected)
	if loc == _session.registry.source_locale:
		_map = _source
	else:
		_map = _session.registry.open_map(_map_id(), loc)  # empty if no file yet
		if _map == null:
			push_error("TimelineTextMapEditor: '%s' (%s) is unreadable" % [_map_id(), loc])
			_map = _source
			_loc_pick.select(0)
	_fill()


func _autosave_translation() -> void:
	if _map != null and _map != _source and _map.is_dirty():
		_session.save_working(_map)


## Finds locales by scanning the folder for files matching the template.
## Only works for templates where {locale} is part of the file name.
func _locales_on_disk(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var reg := _session.registry
	var full := reg.resolve_template(reg.template_of(map_id))
	var i := full.find(QuantoDialogueRegistry.LOCALE_TOKEN)
	if i == -1:
		return out
	var head := full.substr(0, i)
	var tail := full.substr(i + QuantoDialogueRegistry.LOCALE_TOKEN.length())
	var prefix := head.get_file()
	for f in DirAccess.get_files_at(head.get_base_dir()):
		if f.begins_with(prefix) and f.ends_with(tail) and f.length() > prefix.length() + tail.length():
			out.append(f.substr(prefix.length(), f.length() - prefix.length() - tail.length()))
	return out


func _fill() -> void:
	_tree.clear()
	var translating := _map != _source
	_tree.columns = 3 if translating else 2
	_tree.set_column_title(0, "ID")
	_tree.set_column_title(1, "Source")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 220)
	if translating:
		_tree.set_column_title(2, "Translation (%s)" % _map.locale)
	var root := _tree.create_item()
	var q := _filter.text.strip_edges().to_lower()
	for id in _source.ids_sorted():
		if id.begins_with(TimelineTextSession.DRAFT):
			continue
		var src := _source.get_text(id)
		if not q.is_empty() and not (id.to_lower().contains(q) or src.to_lower().contains(q)):
			continue
		var it := _tree.create_item(root)
		it.set_text(0, id)
		it.set_metadata(0, id)
		it.set_text(1, src)
		it.set_editable(1, not translating)
		if translating:
			it.set_text(2, _map.get_text(id))
			it.set_editable(2, true)
			_style_translation(it, id, src)


func _style_translation(it: TreeItem, id: String, src: String) -> void:
	it.clear_custom_color(2)
	if not _map.has(id) or _map.get_text(id).is_empty():
		it.set_custom_color(2, Color.GRAY)  # untranslated
		it.set_tooltip_text(2, "Untranslated (falls back to the source text)")
	elif _map.is_stale(id, src):
		it.set_custom_color(2, Color.ORANGE)
		it.set_tooltip_text(2, "The source text changed after this was translated")


func _on_edited() -> void:
	var it := _tree.get_edited()
	var id: String = it.get_metadata(0)
	if _tree.get_edited_column() == 1:
		_source.set_text(id, it.get_text(1))
	else:
		_map.set_text(id, it.get_text(2), TextMap.hash_text(_source.get_text(id)))
		_style_translation(it, id, _source.get_text(id))


func _add_id() -> void:
	if _map != _source:
		push_warning("TimelineTextMapEditor: switch to the source locale to add ids")
		return
	var id := _new_id.text.strip_edges()
	if not TextMap.is_valid_id(id) or _source.has(id):
		push_warning("TimelineTextMapEditor: '%s' is invalid or already exists" % id)
		return
	_source.set_text(id, "")
	_new_id.clear()
	_fill()


func _delete_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	_map.remove(it.get_metadata(0))  # in a translation this just un-translates it
	_fill()


func _add_locale() -> void:
	var loc := _new_loc.text.strip_edges()
	if not TextMap.is_valid_id(loc):
		return
	for i in _loc_pick.item_count:
		if _loc_pick.get_item_text(i) == loc:
			return
	_loc_pick.add_item(loc)
	_loc_pick.select(_loc_pick.item_count - 1)
	_new_loc.clear()
	_load_locale()  # the file is created on first Save


func _save() -> void:
	for m: TextMap in [_source, _map]:
		if m.is_dirty():
			var err := _session.save_working(m)
			if err != OK:
				push_error("TimelineTextMapEditor: cannot save %s/%s (error %d)" % [m.map_id, m.locale, err])
		if _map == _source:
			break
	_fill()
