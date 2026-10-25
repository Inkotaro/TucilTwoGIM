@tool
class_name DialogueBlock
extends PanelContainer
## Base class for every draggable block.
##   block_type(), block_color(), _build_body(), to_event(), from_event()

signal changed
static var context_handler: Callable = Callable()
static var cursor: DialogueBlock = null  # the block arrow keys move from
var body: VBoxContainer
var _built := false

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.NONE

func block_color() -> Color:
	return Color.GRAY

func _build_body(_parent: VBoxContainer) -> void:
	pass
	
func to_event() -> DialogueEvent:
	var event := DialogueEvent.new()
	# Map the block type string to the DialogueEvent.Type enum if applicable
	event.type = block_type()
	return event

func from_event(event: DialogueEvent) -> void:
	# text_edit.text = event.dialogue_text
	pass


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	
	if _built:
		return
	_built = true

	mouse_filter = Control.MOUSE_FILTER_PASS   # let drops bubble up to the EventList

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0, 0, 0, 0.25)
	_style.border_color = block_color()
	_style.border_width_left = 4
	_style.set_corner_radius_all(4)
	_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _style)
	
	var root := VBoxContainer.new()
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var handle := Label.new()
	handle.text = "⠿"
	handle.tooltip_text = "Drag to move"
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.set_drag_forwarding(_get_handle_drag_data, Callable(), Callable())
	header.add_child(handle)

	var title := Label.new()
	title.text = DialogueEvent.get_type_name(block_type()).capitalize()
	title.add_theme_color_override("font_color", block_color())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var delete := Button.new()
	delete.text = "✕"
	delete.flat = true
	delete.tooltip_text = "Delete"
	delete.pressed.connect(_delete)
	header.add_child(delete)

	body = VBoxContainer.new()
	root.add_child(body)
	_build_body(body)


func _get_handle_drag_data(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = "  Moving: %s" % DialogueEvent.get_type_name(block_type()).capitalize()
	set_drag_preview(preview)
	return self


func _delete() -> void:
	var p := get_parent()
	if p:
		p.remove_child(self)
	queue_free()
	
func watch(w: Control) -> void:
	if w is LineEdit:
		w.text_changed.connect(func(_t): changed.emit())
	elif w is TextEdit:
		w.text_changed.connect(func(): changed.emit())
	elif w is OptionButton:
		w.item_selected.connect(func(_i): changed.emit())
	elif w is BaseButton:
		w.toggled.connect(func(_b): changed.emit())
	elif w is Range:
		w.value_changed.connect(func(_v): changed.emit())
var _style: StyleBoxFlat

# in ensure_built(), replace `var style := StyleBoxFlat.new()` with:
#   _style = StyleBoxFlat.new()
# and use `_style` for the lines that follow, including:
#   add_theme_stylebox_override("panel", _style)
static var selection: Array[DialogueBlock] = []
static var clipboard: Array[DialogueEvent] = []

enum Highlight { NONE, MATCH, CURRENT }
var _hl := Highlight.NONE
var _selected := false


func set_highlight(level: Highlight) -> void:
	_hl = level
	_refresh_style()


func set_selected(value: bool) -> void:
	_selected = value
	_refresh_style()


func _refresh_style() -> void:
	if _style == null:
		return
	_style.bg_color = Color(0, 0, 0, 0.25)
	_style.border_color = block_color()
	_style.set_border_width_all(0)
	_style.border_width_left = 4
	match _hl:
		Highlight.MATCH:
			_style.bg_color = Color(1.0, 0.9, 0.4, 0.15)
			_style.border_color = Color(1.0, 0.9, 0.4)
			_style.set_border_width_all(1)
			_style.border_width_left = 4
		Highlight.CURRENT:
			_style.bg_color = Color(1.0, 0.7, 0.2, 0.3)
			_style.border_color = Color(1.0, 0.7, 0.2)
			_style.set_border_width_all(2)
			_style.border_width_left = 4
	if _selected:
		_style.bg_color = Color(0.3, 0.6, 1.0, 0.22)
		_style.border_color = Color(0.4, 0.7, 1.0)
		_style.set_border_width_all(2)
		_style.border_width_left = 4


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().gui_release_focus()
		DialogueBlock.select(self, mb.is_command_or_control_pressed() or mb.shift_pressed)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().gui_release_focus()
		if context_handler.is_valid():
			context_handler.call(self, get_global_mouse_position())
		accept_event()  # innermost block wins, parents don't also open a menu

static func select(block: DialogueBlock, additive: bool) -> void:
	if not additive:
		var was_only := selection.size() == 1 and selection[0] == block
		clear_selection()
		if was_only:
			return  # clicking the sole selected block again deselects it
	if block in selection:
		selection.erase(block)
		block.set_selected(false)
	else:
		selection.append(block)
		block.set_selected(true)
		cursor = block


static func clear_selection() -> void:
	for b in selection:
		if is_instance_valid(b):
			b.set_selected(false)
	selection.clear()

const DRAFT_PREFIX := "DRAFT"
## Context of the tab being edited. Set by TimelineEditor before blocks are built.
static var text_map: TextMap
static var id_prefix := DRAFT_PREFIX
static var resolver: TextResolver
static var clipboard_texts: Dictionary = {}  ## id -> text captured at copy time
static var store: TextMapStore
static var text_locked := false

static func new_text_id() -> String:
	return text_map.generate_id(id_prefix) if text_map else ""


static func read_text(ref: String) -> String:
	if ref.is_empty():
		return ""
	if not TextResolver.parse_ref(ref)[0].is_empty():
		return resolver.resolve(ref) if resolver else ref
	return text_map.get_text(ref) if text_map else ""


static func write_text(id: String, text: String) -> void:
	if text_map:
		text_map.set_text(id, text)
