extends Button

@export var control_name: String = "interact"
@onready var timer: Timer = $Timer

func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)

	timer.timeout.connect(func(): hide())
	timer.start()

func _input(event: InputEvent) -> void:
	var is_touch: bool = event is InputEventScreenTouch or event is InputEventScreenDrag
	var is_mouse: bool = (event is InputEventMouseButton and event.pressed) or event is InputEventMouseMotion

	if is_touch or is_mouse:
		if not visible:
			show()
		timer.start()

func _on_button_down() -> void:
	if not _parse_key_event(true):
		Input.action_press(control_name)

func _on_button_up() -> void:
	if not _parse_key_event(false):
		Input.action_release(control_name)

func _on_pressed() -> void:
	if control_name.begins_with("key_"):
		return

	var ev := InputEventAction.new()
	ev.action = control_name
	ev.pressed = true
	Input.parse_input_event(ev)

func _parse_key_event(is_pressed: bool) -> bool:
	if not control_name.begins_with("key_"):
		return false

	var key_str := control_name.trim_prefix("key_")
	var key_code := OS.find_keycode_from_string(key_str)

	if key_code == Key.KEY_NONE:
		push_warning("Control name '%s' specifies an invalid key: '%s'" % [control_name, key_str])
		return false

	var ev := InputEventKey.new()
	ev.key_label = key_code
	ev.physical_keycode = key_code
	ev.keycode = key_code
	ev.pressed = is_pressed
	Input.parse_input_event(ev)

	return true
