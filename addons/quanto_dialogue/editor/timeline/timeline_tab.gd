class_name TimelineTab
extends RefCounted

var path := ""
var events: Array[DialogueEvent] = []
var history := EditHistory.new()
var dirty := false

var map_id := ""
var imports := PackedStringArray()
var resolver: TimelineTextResolver

# UI
var row: HBoxContainer
var button: Button

func title() -> String:
	var n := path.get_file() if not path.is_empty() else "Untitled"
	return n + (" *" if dirty else "")
