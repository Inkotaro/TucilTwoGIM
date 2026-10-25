@tool
class_name DialogueRunner
extends Control
## In-game usage example. Attach to a Control node and call start().
##
## Text comes from a TextMapStore (default: the shared one). To preview unsaved text,
## pass your own resolver to start().
signal timeline_finished
signal timeline_started

@export var dialog_resource: DialogueDataResource
@export var typewriter_config: TypewriterConfig = TypewriterConfig.new()

## Where text is looked up. Null = TextMapStore.shared().
var text_store: TextMapStore = null

var interpreter := DialogueInterpreter.new()
@onready var choices_container: VBoxContainer = %ChoicesContainer
@onready var speaker_label: Label = %SpeakerLabel
@onready var typewriter_label: RichTextLabel = %TypewriterLabel
@onready var typewriter_timer: Timer = %TypewriterTimer
@onready var typewriter_player: AudioStreamPlayer = %TypewriterPlayer
@onready var finish_player: AudioStreamPlayer = %FinishPlayer
@export var action_name: String = "ui_accept"

var _showing_error := false
var _full_text: String = ""
var _char_index: int = 0
var _total_chars: int = 0
var _scale_fx := ScaleInEffect.new()
var _owned_resolver: TimelineTextResolver = null  # created by start(); released when done


func _ready() -> void:
	visible = false
	_scale_fx.font_size = typewriter_label.get_theme_font_size("normal_font_size") || 16
	typewriter_label.custom_effects.clear()
	typewriter_label.install_effect(_scale_fx)
	interpreter.line_shown.connect(_on_line)
	interpreter.choices_shown.connect(_on_choices)
	interpreter.event_fired.connect(func(key: String, value: String): print("EVENT ", key, " = ", value))
	interpreter.finished.connect(_on_timeline_finished)
	interpreter.started.connect(_on_timeline_started)
	typewriter_timer.timeout.connect(_on_typewriter_timer)


func _exit_tree() -> void:
	_release_resolver()


func _get_step_time() -> float:
	var cps := 30.0
	if typewriter_config != null:
		cps = typewriter_config.characters_per_second
	return 1.0 / maxf(cps, 1.0)


## `resolver` overrides text lookup (the editor passes one that sees unsaved text).
## Without it, a TimelineTextResolver is built from the resource's map_id and imports.
func start(resource: DialogueDataResource, resolver: TextResolver = null) -> void:
	if resource == null:
		push_error("DialogueRunner: Failed to load dialogue resource")
		return
	_release_resolver()
	_showing_error = false
	if resolver == null:
		var store := text_store if text_store != null else TextMapStore.shared()
		_owned_resolver = TimelineTextResolver.new(store, resource.map_id, resource.imports)
		resolver = _owned_resolver
	typewriter_timer.wait_time = _get_step_time()
	interpreter.start(resource, resolver)


## Shows an error in the dialogue box instead of a line, so a failure is visible in game
## (e.g. "Unknown timeline 'intro'"). Press the action key to close it.
## The next start() replaces it.
func show_error(message: String) -> void:
	# Called from another node's _ready(), this node's @onready labels may not exist yet.
	if not is_node_ready():
		await ready
	show()  # in case the dialogue UI is hidden until a timeline starts
	typewriter_timer.stop()
	_clear_buttons()
	_showing_error = true
	speaker_label.text = "ERROR"
	typewriter_label.text = "[color=red]%s[/color]\n\n[color=gray](press to close)[/color]" % message.replace("[", "[lb]")
	typewriter_label.visible_characters = -1
	_char_index = 0
	_total_chars = 0


func _close_error() -> void:
	_showing_error = false
	typewriter_label.text = ""
	speaker_label.text = ""
	_clear_buttons()
	hide()
	timeline_finished.emit()


func _release_resolver() -> void:
	if is_instance_valid(_owned_resolver):
		_owned_resolver.release()
	_owned_resolver = null


func _unhandled_input(event: InputEvent) -> void:
	if _showing_error:
		if event.is_action_pressed(action_name):
			get_viewport().set_input_as_handled()
			_close_error()
		return  # nothing is running; don't advance the interpreter
	if event.is_action_pressed(action_name):
		if _char_index >= _total_chars:
			interpreter.advance()
		elif typewriter_config != null and typewriter_config.allow_skip:
			_on_skip()


func _on_timeline_started(timeline: String) -> void:
	visible = true
	timeline_started.emit()


func _on_timeline_finished(timeline: String) -> void:
	visible = false
	typewriter_label.text = "(end)"
	typewriter_label.visible_characters = 5
	_clear_buttons()
	_release_resolver()
	timeline_finished.emit()


func _on_typewriter_finished() -> void:
	finish_player.play()


func _on_skip() -> void:
	typewriter_timer.stop()
	for i in range(_char_index, _total_chars):
		_scale_fx.reveal_times[i] = 0
	_char_index = _total_chars
	typewriter_label.visible_characters = _char_index
	_on_typewriter_finished()


func _on_line(speaker: String, text: String, _text_id: String) -> void:
	speaker_label.text = "???" if speaker.is_empty() else speaker
	_full_text = text
	_scale_fx.reset()
	typewriter_label.text = "[scale_in]%s[/scale_in]" % text
	typewriter_label.visible_characters = 0
	_total_chars = typewriter_label.get_total_character_count()
	_char_index = 0
	_clear_buttons()
	typewriter_timer.start()


func _on_choices(options: Array) -> void:
	typewriter_label.text = ""
	_clear_buttons()
	for i in options.size():
		_add_button(options[i], interpreter.choose_option.bind(i))


func _add_button(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	choices_container.add_child(b)


func _clear_buttons() -> void:
	for c in choices_container.get_children():
		choices_container.remove_child(c)
		c.queue_free()


func _on_typewriter_timer() -> void:
	_scale_fx.mark_revealed(_char_index)
	_char_index += 1
	typewriter_label.visible_characters = _char_index
	typewriter_player.play()
	if _char_index >= _total_chars:
		typewriter_timer.stop()
		_on_typewriter_finished()
		return
