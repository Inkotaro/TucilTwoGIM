@tool
class_name TimelineEditor
## Minimalistic dialogue editor for Godot.
extends Control

const ACTION_PREFIX := "quanto_dialogue_"
const MENU_NEW_PROJECT := 10
const MENU_OPEN_PROJECT := 11
const MENU_EXPORT := 12
const MENU_PROJECTS := 13

@onready var event_list: EventList = %EventList
@onready var empty_event_list: VBoxContainer = %EmptyEventList
@onready var file_menu_button: MenuButton = %FileMenuButton
@onready var project_label: Label = %ProjectLabel
@onready var path_label: Label = %PathLabel
@onready var map_label: Label = %MapLabel
@onready var run_button: Button = %RunButton
@onready var empty_new_button: Button = %EmptyNewButton
@onready var open_file_dialog: FileDialog = %OpenFileDialog
@onready var save_file_dialog: FileDialog = %SaveFileDialog
@onready var runner: DialogueRunner = %DialogueRunner
@onready var tab_container: TabContainer = %TabContainer
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var search_edit: LineEdit = %SearchEdit  # filters tabs
@onready var block_search_edit: LineEdit = %BlockSearchEdit  # searches blocks
@onready var tab_list: VBoxContainer = %TabList
@onready var commit_timer: Timer = %CommitTimer
@onready var _welcome: QuantoProjectDialog = %ProjectDialog  # start-up prompt: new / recent project
var _migrate_dialog: TimelineMigrateDialog


var _map_picker: TimelineMapPicker
var _registry_editor: QuantoRegistryEditor
var _text_editor: TimelineTextMapEditor

var _loading := false  # true while event_list is being rebuilt (suppresses undo snapshots)
var _restoring := false  # true while tabs are being reopened from the registry
var _project_dialog := FileDialog.new()  # folder picker for New / Open Project
var _project_mode := ""                  # "new" or "open"
var _notice := AcceptDialog.new()        # shows problems the user must see
var _export_dialog: QuantoExportDialog
var _from_welcome := false               # the folder picker was opened from the prompt
var _welcome_shown := false

var _text: TimelineTextSession
var _preview: TimelinePreview
var _tabs: TimelineTabManager
var _actions: TimelineBlockActions
var _nav: TimelineNavigator
var _keys: TimelineInput
var _block_search: TimelineBlockSearch
var _menu: TimelineContextMenu

func _update_list_visibility() -> void:
	var has_tab := _tabs.active != null
	event_list.visible = has_tab
	empty_event_list.visible = not has_tab

func _ready() -> void:
	QuantoShortcutActions.ensure_in_input_map()
	_welcome.visible = false  # only shown by _ask_welcome()
	_text = TimelineTextSession.new()
	_build_modules()
	_connect_ui()
	_setup_file_dialogs()
	_update_project_label()
	event_list.visible = _tabs.active != null
	empty_event_list.visible = _tabs.active == null
	var restored := _restore_tabs()
	# No project (first run, or the remembered folder is gone): the prompt is not optional.
	if QuantoDialogueLocator.show_startup_dialog() or not _text.registry.is_usable():
		_schedule_welcome()
	elif not restored and !Engine.is_editor_hint():
		_on_new()
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)


func _exit_tree() -> void:
	if _menu:
		_menu.teardown()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and _keys.handle(event, get_viewport()):
		get_viewport().set_input_as_handled()


# --- setup --------------------------------------------------------------------
func _build_modules() -> void:
	_tabs = TimelineTabManager.new(tab_list)
	_tabs.live_events = event_list.to_array
	_tabs.tab_leaving.connect(_on_tab_leaving)
	_tabs.tab_entered.connect(_on_tab_entered)
	_tabs.active_closed.connect(_on_active_closed)

	_actions = TimelineBlockActions.new(event_list)
	_actions.edited.connect(_on_list_changed)
	_nav = TimelineNavigator.new(event_list)
	_block_search = TimelineBlockSearch.new(block_search_edit, event_list)
	_menu = TimelineContextMenu.new(self, _actions, ACTION_PREFIX)
	_keys = TimelineInput.new(event_list, _nav, _build_shortcuts(), ACTION_PREFIX)

	_preview = TimelinePreview.new(runner, tab_container)
	_preview.finished.connect(_focus_editor)

	_map_picker = TimelineMapPicker.new()
	add_child(_map_picker)
	_map_picker.map_picked.connect(_on_map_picked)

	_text_editor = TimelineTextMapEditor.new()
	add_child(_text_editor)
	_text_editor.closed.connect(_on_text_editor_closed)

	_registry_editor = QuantoRegistryEditor.new()
	add_child(_registry_editor)
	_registry_editor.changed.connect(_on_registry_edited)
	_registry_editor.map_switch_requested.connect(_on_map_switch_requested)
	_registry_editor.timeline_open_requested.connect(_on_registry_open_timeline)

	_project_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_project_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_project_dialog.dir_selected.connect(_on_project_folder_picked)
	_project_dialog.canceled.connect(_on_project_dialog_canceled)
	add_child(_project_dialog)
	_notice.title = "Dialogue project"
	add_child(_notice)

	_export_dialog = QuantoExportDialog.new()
	add_child(_export_dialog)
	_export_dialog.export_requested.connect(_on_export_requested)

	# _welcome comes from the scene (%ProjectDialog); only connect it here
	_welcome.project_chosen.connect(_on_welcome_project_chosen)
	_welcome.new_requested.connect(func(): _from_welcome = true; _ask_project_folder("new"))
	_welcome.browse_requested.connect(func(): _from_welcome = true; _ask_project_folder("open"))

	# child of the registry editor, because it is exclusive and would block a sibling
	_migrate_dialog = TimelineMigrateDialog.new()
	_registry_editor.add_child(_migrate_dialog)
	_migrate_dialog.migrate_chosen.connect(_on_migrate_chosen)
	_migrate_dialog.canceled.connect(func(): _registry_editor.show_notice("Switch cancelled."))


func _on_file_menu_pressed(id: int) -> void:
	if id in [0, 1, 4, 5, MENU_EXPORT] and not _require_project():  # need a project
		return
	match id:
		0: _on_new()
		1: _on_open()
		2: _on_save()
		3: _on_save_as()
		4:
			var cur := _tabs.active.map_id if _tabs.active else ""
			_registry_editor.open(_text.registry, cur, _current_timeline_id())
		5:
			var map_id := _tabs.active.map_id if _tabs.active else _text.registry.default_map
			_text_editor.open(_text, map_id)
		MENU_NEW_PROJECT: _ask_project_folder("new")
		MENU_OPEN_PROJECT: _ask_project_folder("open")
		MENU_EXPORT: _export_dialog.open()
		MENU_PROJECTS: _ask_welcome()  # the project list; works without a project too


## Registry id of the active timeline, "" if there is none or it was never saved.
func _current_timeline_id() -> String:
	var tab := _tabs.active
	if tab == null or tab.path.is_empty():
		return ""
	return _text.registry.timeline_id_of_file(tab.path)


func _on_registry_open_timeline(timeline_id: String) -> void:
	var file := _text.registry.timeline_path(timeline_id)
	if file.is_empty():
		_registry_editor.show_notice("Unknown timeline '%s'." % timeline_id)
		return
	_load(file)  # switches to the tab if it is already open
	_registry_editor.set_current_timeline(_current_timeline_id())
	_registry_editor.show_notice("Opened '%s'." % timeline_id)


func _on_map_switch_requested(map_id: String) -> void:
	var tab := _tabs.active
	if tab == null:
		_registry_editor.show_notice("No timeline is open.")
		return
	_flush_active()  # tab.events must be current before migrating
	var pre := _text.preview_migration(tab, map_id)
	if not String(pre.error).is_empty():
		_registry_editor.show_notice("Can't switch: " + String(pre.error))
		return
	_registry_editor.show_notice("Choose how to switch to '%s'..." % map_id)
	_migrate_dialog.ask(tab.map_id, map_id, pre)


func _on_migrate_chosen(target_id: String, mode: int) -> void:
	var tab := _tabs.active
	if tab == null:
		_registry_editor.show_notice("No timeline is open.")
		return
	_flush_active()
	_text.end_recording()  # recording was on the old map
	var report := _text.migrate_tab(tab, target_id, mode,
			func(mapping: Dictionary): TextBinding.remap_ids(tab.events, mapping))
	# On success this rebuilds the list on the new map and resets undo
	# (deltas can't cross maps). On failure it re-enters the old map.
	_on_tab_entered(tab)
	if report.ok:
		tab.dirty = true
		_refresh_ui()
		_registry_editor.set_current_map(target_id)
	_registry_editor.show_notice(report.message)


func _on_new() -> void:
	event_list.visible = _tabs.active != null
	empty_event_list.visible = _tabs.active == null
	if _require_project():
		_map_picker.ask(_text.registry)


func _on_map_picked(map_id: String, is_new: bool) -> void:
	if is_new and not _text.register_map(map_id):
		push_warning("TimelineEditor: could not register map '%s'" % map_id)
		return
	var no_events: Array[DialogueEvent] = []
	_tabs.open("", no_events, map_id, PackedStringArray())
	event_list.visible = _tabs.active != null
	empty_event_list.visible = _tabs.active == null


func _on_registry_edited() -> void:
	if not _text.reload_maps():
		push_warning("TimelineEditor: save your text first; the registry change applies after")
		return
	if _tabs.active:
		_on_tab_entered(_tabs.active)


func _on_text_editor_closed() -> void:
	if _tabs.active == null:
		return
	_flush_active()
	_rebuild_list(_tabs.active.events)  # refresh blocks that show text


func _build_shortcuts() -> Dictionary:
	var named := {
		"new": _on_new,
		"open": _on_open,
		"save": _on_save,
		"save_as": _on_save_as,
		"close_tab": _close_active_tab,
		"run": _on_run_pressed,
		"undo": _on_undo,
		"redo": _on_redo,
		"next_tab": _tabs.cycle.bind(1),
		"prev_tab": _tabs.cycle.bind(-1),
		"copy_block": _actions.copy,
		"cut_block": _actions.cut,
		"paste_block": _actions.paste,
		"duplicate_block": _actions.duplicate,
		"delete_block": _actions.delete_selected,
		"add_event": _actions.add_event_in_scope,
		"select_all": _actions.select_all_in_scope,
	}
	var out := {}
	for k in named:
		out[ACTION_PREFIX + k] = named[k]
	# NOTE: these keys are NOT prefixed (same as before); make sure the InputMap
	# actually defines "tab_1".."tab_9" or they will never fire.
	for i in 9:
		out["tab_%d" % (i + 1)] = _tabs.jump.bind(i)
	return out


func _connect_ui() -> void:
	var popup := file_menu_button.get_popup()
	popup.id_pressed.connect(_on_file_menu_pressed)
	open_file_dialog.file_selected.connect(_load)
	save_file_dialog.file_selected.connect(_save)
	run_button.pressed.connect(_on_run_pressed)
	undo_button.pressed.connect(_on_undo)
	redo_button.pressed.connect(_on_redo)
	search_edit.text_changed.connect(_tabs.set_filter)
	commit_timer.timeout.connect(_commit_snapshot)
	event_list.changed.connect(_on_list_changed)
	empty_new_button.pressed.connect(_on_new)


func _setup_file_dialogs() -> void:
	_prepare_timeline_dialog(open_file_dialog)
	_prepare_timeline_dialog(save_file_dialog)


## Timeline dialogs start in the project's timelines folder. Inside this Godot project
## they browse res://; for a project elsewhere they browse the file system.
func _prepare_timeline_dialog(d: FileDialog) -> void:
	if not _text.registry.is_usable():
		return  # no project, no folder (the dialogs are not opened without one)
	var dir := QuantoDialogueProject.timelines_dir(_text.registry)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if dir.begins_with("res://"):
		d.access = FileDialog.ACCESS_RESOURCES
		d.current_dir = dir
	else:
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.current_dir = ProjectSettings.globalize_path(dir)


func _is_plugin() -> bool:
	return Engine.is_editor_hint()


func _on_gui_focus_changed(node: Control) -> void:
	if (node is LineEdit or node is TextEdit) and event_list.is_ancestor_of(node):
		DialogueBlock.clear_selection()




func _on_active_closed() -> void:
	commit_timer.stop()
	_text.end_recording()
	_update_list_visibility()
	_persist_tabs.call_deferred()

func _on_tab_leaving(_t) -> void:
	if _restoring:
		return  # event_list isn't showing this tab, so flushing would overwrite its events
	_flush_active()
	_text.end_recording()


func _on_tab_entered(tab: TimelineTab) -> void:
	if _restoring:
		return
	_update_list_visibility()
	_text.enter(tab)
	_rebuild_list(tab.events)
	tab.history.reset(event_list.to_array())
	_text.begin_recording()
	_refresh_ui()
	_persist_tabs.call_deferred()


func _rebuild_list(events: Array[DialogueEvent]) -> void:
	_loading = true
	event_list.from_array(events)
	_loading = false


func _close_active_tab() -> void:
	if _tabs.active:
		_tabs.close(_tabs.active)


func _flush_active() -> void:
	var tab := _tabs.active
	if tab == null:
		return
	_settle_pending()
	tab.events = event_list.to_array()


func _settle_pending() -> void:
	if not commit_timer.is_stopped():
		commit_timer.stop()
		_commit_snapshot()


func _on_list_changed() -> void:
	if _loading or _tabs.active == null:
		return
	undo_button.disabled = false
	commit_timer.start()  # restarts the debounce


func _commit_snapshot() -> void:
	var tab := _tabs.active
	if tab == null:
		return
	var delta := _text.end_recording()
	tab.history.commit(event_list.to_array(), delta)
	_text.begin_recording()
	tab.dirty = true
	_refresh_ui()


func _on_undo() -> void:
	_step_history(true)


func _on_redo() -> void:
	_step_history(false)


func _step_history(undo: bool) -> void:
	var tab := _tabs.active
	if tab == null:
		return
	_settle_pending()
	var h := tab.history
	var snapshot: Array[DialogueEvent]
	if undo and h.can_undo():
		snapshot = h.undo()
	elif not undo and h.can_redo():
		snapshot = h.redo()
	else:
		return
	_text.end_recording()  # discard
	_text.apply_delta(h.last_delta, h.last_reverse)
	_apply_snapshot(snapshot)
	_text.begin_recording()


func _apply_snapshot(snapshot: Array[DialogueEvent]) -> void:
	_rebuild_list(snapshot)
	_tabs.active.history.replace_current(event_list.to_array())
	_tabs.active.dirty = true
	_refresh_ui()


## Registry id when the timeline is registered, else the file name.
func _timeline_name(tab: TimelineTab) -> String:
	if tab.path.is_empty():
		return "Untitled"
	var id := _text.registry.timeline_id_of_file(tab.path)
	return id if not id.is_empty() else tab.path.get_file().get_basename()


func _refresh_ui() -> void:
	_update_project_label()
	_tabs.refresh()
	var tab := _tabs.active
	if tab:
		path_label.text = "Timeline: %s" % _timeline_name(tab)
		path_label.tooltip_text = "Project: %s\n%s" % [
				QuantoDialogueProject.folder_of(_text.registry),
				tab.path if not tab.path.is_empty() else "(unsaved)"]
		_update_map_label(tab)
	else:
		path_label.text = ""
		map_label.text = ""
	undo_button.disabled = tab == null or not tab.history.can_undo()
	redo_button.disabled = tab == null or not tab.history.can_redo()


## Shows the open project's folder name; works without a tab and without a project.
func _update_project_label() -> void:
	var reg := _text.registry
	if not reg.is_usable():
		project_label.text = "No project  |"
		project_label.tooltip_text = "Create or open a project (File menu)"
		return
	project_label.text = "Project: %s  |" % QuantoDialogueProject.name_of(reg)
	project_label.tooltip_text = QuantoDialogueProject.folder_of(reg)


func _update_map_label(tab: TimelineTab) -> void:
	var registered := _text.registry.has_map(tab.map_id)
	map_label.text = "|  TextMap: %s%s" % [tab.map_id, "" if registered else "  (not registered)"]
	map_label.tooltip_text = _text.registry.path_for(tab.map_id, _text.registry.source_locale) \
			if registered else "This map id is not in the registry yet."
	if registered:
		map_label.remove_theme_color_override("font_color")
	else:
		map_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))


# --- registry -----------------------------------------------------------------
## "New Project": pick or create an empty folder. "Open Project": pick a project folder.
func _ask_project_folder(mode: String) -> void:
	_project_mode = mode
	_project_dialog.title = "New Project: pick or create a folder" if mode == "new" \
			else "Open Project: pick the folder with %s" % QuantoDialogueRegistry.FILE_NAME
	var start := QuantoDialogueProject.folder_of(_text.registry)
	if start.is_empty():
		start = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_project_dialog.current_dir = ProjectSettings.globalize_path(start)
	_project_dialog.popup_centered_ratio(0.6)


## Shows the start-up prompt once, as soon as the editor is actually visible (a dock or
## main-screen plugin may be hidden when Godot starts).
func _schedule_welcome() -> void:
	if is_visible_in_tree():
		_show_welcome.call_deferred()
	else:
		visibility_changed.connect(_on_first_visible)


func _on_first_visible() -> void:
	if not is_visible_in_tree():
		return
	visibility_changed.disconnect(_on_first_visible)
	_show_welcome.call_deferred()


func _show_welcome() -> void:
	if _welcome_shown:
		return
	_welcome_shown = true
	_ask_welcome()


## Exports the project (registry, TextMaps, timelines) into `dir`. Only what is saved on
## disk is exported, so unsaved timelines block it; texts are saved first.
func _on_export_requested(dir: String, prefix: String) -> void:
	if not _require_project():
		return
	for t: TimelineTab in _tabs.tabs:
		if t.dirty:
			_export_dialog.show_result("Save your open timelines first: only saved files are exported.")
			return
	_flush_active()
	var err := _text.save_text()
	if err != OK:
		_export_dialog.show_result("Could not save the text maps (error %d); nothing was exported." % err)
		return
	var n := _text.registry.publish_to(dir, prefix)
	if n < 0:
		_export_dialog.show_result("Export failed: could not write the registry to %s" % dir)
		push_error("TimelineEditor: export to %s failed" % dir)
		return
	_export_dialog.show_result("Exported %d file(s) to %s (prefix: %s)" % [
			n, dir, prefix if not prefix.is_empty() else QuantoDialogueRegistry.PUBLISH_SUBDIR])
	if dir.begins_with("res://"):
		_rescan_project()


func _ask_welcome() -> void:
	_welcome.ask(QuantoDialogueProject.folder_of(_text.registry), _text.registry.is_usable())


## Timelines, maps and text all live in a project, so these need one. Without a project
## the start-up prompt opens instead.
func _require_project() -> bool:
	if _text.registry.is_usable():
		return true
	_ask_welcome()
	return false


func _on_welcome_project_chosen(folder: String) -> void:
	var reg := QuantoDialogueProject.open(folder)
	if not reg.is_usable():
		_alert("Cannot open the project in %s:\n%s" % [folder, reg.status_message])
		QuantoDialogueLocator.remove_recent(folder)
		return
	_switch_project(reg)


## Cancelling the folder picker returns to the start-up prompt if it came from there.
func _on_project_dialog_canceled() -> void:
	if _from_welcome:
		_from_welcome = false
		_ask_welcome()


func _on_project_folder_picked(folder: String) -> void:
	_from_welcome = false
	folder = ProjectSettings.localize_path(folder)  # res:// when inside this Godot project
	var reg: QuantoDialogueRegistry
	if _project_mode == "new":
		if folder == "res://" or folder.is_empty():
			_alert("Pick or create a sub-folder for the project, not the Godot project root.")
			return
		if QuantoDialogueProject.is_project(folder):
			_alert("%s already contains a dialogue project.\nUse Open Project instead." % folder)
			return
		reg = QuantoDialogueProject.create(folder)
	else:
		if not QuantoDialogueProject.is_project(folder):
			_alert("No dialogue project in %s\n(%s not found).\nUse New Project to create one." % [
					folder, QuantoDialogueRegistry.FILE_NAME])
			return
		reg = QuantoDialogueProject.open(folder)
	if not reg.is_usable():
		_alert("Cannot use the project in %s:\n%s" % [folder, reg.status_message])
		return
	_switch_project(reg)


## Replaces the current project. Refuses while there is unsaved work, then closes the old
## project's tabs (the session is remembered per project) and reopens the new one's.
func _switch_project(reg: QuantoDialogueRegistry) -> void:
	if _text.has_dirty():
		_alert("Save your text before switching project.")
		return
	for t: TimelineTab in _tabs.tabs:
		if t.dirty:
			_alert("Save or close the unsaved timeline(s) before switching project.")
			return
	_flush_active()
	_persist_tabs()  # remember the old project's tabs while the old registry is current
	_restoring = true
	_text.end_recording()
	for t: TimelineTab in _tabs.tabs.duplicate():
		_tabs.close(t)
	_restoring = false
	_text.adopt(reg, _tabs.tabs)
	var folder := QuantoDialogueProject.folder_of(reg)
	QuantoDialogueLocator.set_current_project(folder)
	QuantoDialogueLocator.add_recent(folder)
	_update_project_label()
	_setup_file_dialogs()  # point the open/save dialogs at the new project's folder
	if not _restore_tabs():
		event_list.visible = false
		empty_event_list.visible = true
		_refresh_ui()


func _alert(message: String) -> void:
	push_warning("TimelineEditor: " + message)
	_notice.dialog_text = message
	_notice.popup_centered()


func _on_register_map() -> void:
	var tab := _tabs.active
	if tab == null:
		return
	_flush_active()
	if _text.register_map(tab.map_id):
		_on_tab_entered(tab)


## Makes sure the timeline file is listed in the registry (and the registry is saved).
## Called after saving and after opening a file, so exports and the in-game
## loader can find every timeline you've touched.
func _register_timeline(path: String) -> void:
	var reg := _text.registry
	if not reg.is_usable() or path.is_empty():
		return
	if not reg.timeline_id_of_file(path).is_empty():
		return  # already registered
	var id := reg.register_timeline_file(path)
	var err := reg.save_file()
	if err != OK:
		push_warning("TimelineEditor: registered timeline '%s' but could not save the registry (error %d)" % [id, err])


## Remembers which registered timelines are open (and which is active), so the next
## start can reopen them. Unsaved tabs have no registry id and are not remembered.
func _persist_tabs() -> void:
	if _restoring or not _text.registry.is_usable():
		return
	var reg := _text.registry
	var ids := PackedStringArray()
	for t: TimelineTab in _tabs.tabs:
		var id := reg.timeline_id_of_file(t.path) if not t.path.is_empty() else ""
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	var active_id := ""
	if _tabs.active != null and not _tabs.active.path.is_empty():
		active_id = reg.timeline_id_of_file(_tabs.active.path)
	QuantoDialogueLocator.set_open_timelines(reg.path, ids, active_id)

## Opens every timeline in the registry. Previously open ones come first, and the
## remembered active one is selected (else the first). Returns true if any tab opened.
func _restore_tabs() -> bool:
	var reg := _text.registry
	if not reg.is_usable():
		return false

	var ids := PackedStringArray()
	for id in QuantoDialogueLocator.open_timelines(reg.path):
		if reg.has_timeline(id) and not ids.has(id):
			ids.append(id)
	for id in reg.timeline_ids():
		if not ids.has(id):
			ids.append(id)
	if ids.is_empty():
		_update_list_visibility()
		return false

	_restoring = true
	var wanted := QuantoDialogueLocator.active_timeline(reg.path)
	var active_tab: TimelineTab = null
	var first_tab: TimelineTab = null
	for id in ids:
		var file := reg.timeline_path(id)
		var tab := _tabs.find_by_path(file)
		if tab == null:
			var data := reg.open_timeline(id)  # null = warned
			if data == null:
				continue
			_tabs.open(file, data.events, data.map_id, data.imports)
			tab = _tabs.active
		if first_tab == null:
			first_tab = tab
		if id == wanted:
			active_tab = tab
	_restoring = false

	var target := active_tab if active_tab != null else first_tab
	if target == null:
		_update_list_visibility()
		return false
	if target == _tabs.active:
		_on_tab_entered(target)  # switch_to would ignore an already-active tab
	else:
		_tabs.switch_to(target)  # fires tab_leaving / tab_entered normally
	_persist_tabs()
	return true


# --- files --------------------------------------------------------------------
func _on_open() -> void:
	if not _require_project():
		return
	_prepare_timeline_dialog(open_file_dialog)
	open_file_dialog.popup_centered_ratio(0.6)


func _on_save() -> void:
	var tab := _tabs.active
	if tab == null:
		return
	if tab.path.is_empty():
		_on_save_as()
	else:
		_save(tab.path)


func _on_save_as() -> void:
	_prepare_timeline_dialog(save_file_dialog)
	save_file_dialog.popup_centered_ratio(0.6)


func _save(path: String) -> void:
	var tab := _tabs.active
	if tab == null:
		return
	path = QuantoDialogueProject.localize(_text.registry, path)
	_flush_active()
	if DialogueBlock.text_locked:
		push_warning("TimelineEditor: TextMap unavailable; saved the timeline without text")
	elif not _save_text(tab, path):
		return
	var data := DialogueDataResource.new()
	data.map_id = tab.map_id
	data.imports = tab.imports
	data.events = tab.events
	if DialogueDataResource.save_file(path, data):
		tab.path = path
		tab.dirty = false
		_register_timeline(path)
		_persist_tabs()
		DialogueBlock.id_prefix = TimelineTextSession.prefix_for(path)
		_refresh_ui()
		if path.begins_with("res://"):
			_rescan_project()


## Asks the Godot editor to pick up new files. Does nothing without an editor instance.
func _rescan_project() -> void:
	if not Engine.has_singleton("EditorInterface"):
		return
	# Untyped on purpose: the EditorInterface class doesn't exist in export templates.
	var ei = Engine.get_singleton("EditorInterface")
	if ei == null:
		return
	var fs = ei.get_resource_filesystem()
	if fs != null:
		fs.scan()


## Assigns final ids, then writes the text map. False if the text could not be saved.
func _save_text(tab: TimelineTab, path: String) -> bool:
	var mapping := _text.assign_ids(tab, path)
	if not mapping.is_empty():
		TextBinding.remap_ids(tab.events, mapping)
		_rebuild_list(tab.events)
		tab.history.reset(event_list.to_array())  # old snapshots hold the old ids
		_text.begin_recording()
	var err := _text.save_text()
	if err != OK:
		push_error("TimelineEditor: cannot save text map '%s' (error %d)" % [tab.map_id, err])
		return false
	return true


func _load(path: String) -> void:
	path = QuantoDialogueProject.localize(_text.registry, path)
	var existing := _tabs.find_by_path(path)
	if existing:
		_tabs.switch_to(existing)
		return
	var resource := DialogueDataResource.load_file(path)
	if resource == null:
		push_warning("TimelineEditor: failed to load %s" % path)
		return
	_register_timeline(path)
	_tabs.open(path, resource.events, resource.map_id, resource.imports)


# --- running ------------------------------------------------------------------
func _on_run_pressed() -> void:
	run_button.release_focus()
	runner.grab_focus()
	_run()


func _run() -> void:
	var tab := _tabs.active
	if tab == null:
		return
	var temp_resource := DialogueDataResource.new()
	temp_resource.map_id = tab.map_id
	temp_resource.imports = tab.imports
	temp_resource.events = event_list.to_array()
	if temp_resource.events.is_empty():
		push_warning("TimelineEditor: Cannot run empty timeline.")
		return
	_preview.run(temp_resource, tab.resolver)


func _focus_editor() -> void:
	grab_focus()
	event_list.grab_focus()
