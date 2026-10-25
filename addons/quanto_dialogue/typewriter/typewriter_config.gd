@tool
class_name TypewriterConfig
extends Resource

@export_group("Speed Settings")
@export var characters_per_second: float = 30.0
@export var punctuation_pause: float = 0.15

@export_group("Behaviour")
@export var allow_skip: bool = true

@export_group("Audio")
@export var type_sound: AudioStream
