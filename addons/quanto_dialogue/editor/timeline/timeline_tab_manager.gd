@tool
class_name TimelineTabManager
extends RefCounted
## Owns the open tabs, their sidebar rows, and the tab filter.
## It knows nothing about the event list: the editor reacts to the signals.

signal tab_leaving(tab: TimelineTab)  ## emitted while `active` is still the old tab
signal tab_entered(tab: TimelineTab)  ## emitted after `active` changed
signal active_closed

var tabs: Array[TimelineTab] = []
var active: TimelineTab = null
var filter := ""
## Returns the live events of the active tab (its stored events are stale until flush).
var live_events: Callable

var _container: VBoxContainer
var _group := ButtonGroup.new()


func _init(container: VBoxContainer) -> void:
	_container = container


func open(path := "", events: Array[DialogueEvent] = [], map_id := "", imports := PackedStringArray()) -> void:
	var tab := TimelineTab.new()
	tab.path = path
	tab.events = events
	tab.map_id = map_id
	tab.imports = imports
	tabs.append(tab)
	_add_row(tab)
	switch_to(tab)


func find_by_path(path: String) -> TimelineTab:
	for t in tabs:
		if t.path == path:
			return t
	return null


func switch_to(tab: TimelineTab) -> void:
	if tab == active:
		return
	tab_leaving.emit(active)
	active = tab
	tab.button.set_pressed_no_signal(true)
	tab_entered.emit(tab)


func close(tab: TimelineTab) -> void:
	var idx := tabs.find(tab)
	if idx == -1:
		return
	tabs.remove_at(idx)
	tab.row.queue_free()
	if tab != active:
		return
	active = null
	active_closed.emit()
	if tabs.is_empty():
		open()
	else:
		switch_to(tabs[mini(idx, tabs.size() - 1)])


func jump(index: int) -> void:
	if index < tabs.size():
		switch_to(tabs[index])


func cycle(step: int) -> void:
	if tabs.size() < 2 or active == null:
		return
	switch_to(tabs[posmod(tabs.find(active) + step, tabs.size())])


func set_filter(text: String) -> void:
	filter = text.strip_edges().to_lower()
	_apply_filter()


## Refresh titles and tooltips, then re-apply the filter.
func refresh() -> void:
	for t in tabs:
		t.button.text = t.title()
		t.button.tooltip_text = t.path
	_apply_filter()


func _apply_filter() -> void:
	for t in tabs:
		t.row.visible = filter.is_empty() or t == active or _matches(t)


func _matches(t: TimelineTab) -> bool:
	if t.title().to_lower().contains(filter) or t.path.to_lower().contains(filter):
		return true
	var events: Array[DialogueEvent] = live_events.call() if t == active and live_events.is_valid() else t.events
	for e in events:
		if e.get_search_text().to_lower().contains(filter):
			return true
	return false


func _add_row(tab: TimelineTab) -> void:
	var row := HBoxContainer.new()

	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _group
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(switch_to.bind(tab))

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.pressed.connect(close.bind(tab))

	row.add_child(btn)
	row.add_child(close_btn)
	_container.add_child(row)
	tab.row = row
	tab.button = btn
