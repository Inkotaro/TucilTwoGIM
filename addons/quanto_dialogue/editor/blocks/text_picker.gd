@tool
class_name TextPicker
extends PopupPanel
## Searchable list of text ids from the working map and the imported maps.

signal picked(ref: String)

var _filter: LineEdit
var _list: ItemList


func _init() -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 320)
	add_child(box)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Search id or text"
	_filter.clear_button_enabled = true
	box.add_child(_filter)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)

	_filter.text_changed.connect(func(_t): _rebuild())
	_filter.text_submitted.connect(func(_t): _pick(0))  # Enter picks the first match
	_list.item_clicked.connect(func(i, _pos, _btn): _pick(i))
	_list.item_activated.connect(_pick)
	popup_hide.connect(func(): _filter.text = "")


func open_at(anchor: Control) -> void:
	_filter.text = ""
	_rebuild()
	var pos := Vector2i(anchor.get_global_rect().position + Vector2(0, anchor.size.y))
	popup_on_parent(Rect2i(pos, Vector2i(460, 340)))
	_filter.grab_focus()


func _rebuild() -> void:
	_list.clear()
	var q := _filter.text.strip_edges().to_lower()
	_add_map(DialogueBlock.text_map, "", q)
	var r := DialogueBlock.resolver as TimelineTextResolver
	var store := DialogueBlock.store
	if r and store:
		for imp in r.imports:
			_add_map(store.get_map(imp, store.registry.source_locale), imp, q)


func _add_map(map: TextMap, prefix: String, q: String) -> void:
	if map == null:
		return
	for id in map.ids_sorted():
		var text := map.get_text(id)
		var ref := id if prefix.is_empty() else "%s:%s" % [prefix, id]
		if not q.is_empty() and not ref.to_lower().contains(q) and not text.to_lower().contains(q):
			continue
		var preview := text.replace("\n", " ")
		if preview.length() > 50:
			preview = preview.substr(0, 50) + "…"
		var i := _list.add_item("%s    %s" % [ref, preview])
		_list.set_item_metadata(i, ref)
		_list.set_item_tooltip(i, text)


func _pick(i: int) -> void:
	if i < 0 or i >= _list.item_count:
		return
	picked.emit(_list.get_item_metadata(i))
	hide()
