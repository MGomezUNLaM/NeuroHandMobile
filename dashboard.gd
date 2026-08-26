extends Control

signal request_tab_change(index: int)

const DESIGN_SIZE := Vector2(1080.0, 2340.0)

@onready var _main_column: VBoxContainer = $MainColumn
@onready var btn_comenzar: Button = %BtnComenzar
@onready var activity_2: PanelContainer = $MainColumn/Activity2
@onready var activity_3: PanelContainer = $MainColumn/Activity3
@onready var history_widget: PanelContainer = $MainColumn/HistoryWidget

func _ready() -> void:
	if btn_comenzar:
		btn_comenzar.pressed.connect(_on_start_pressed)
	if activity_2:
		activity_2.gui_input.connect(_on_activity_2_input)
	if activity_3:
		activity_3.gui_input.connect(_on_activity_3_input)
	if history_widget:
		history_widget.gui_input.connect(_on_history_input)

func _on_start_pressed() -> void:
	var session_game = load("res://session_game.tscn")
	if session_game:
		get_tree().change_scene_to_packed(session_game)

func _on_activity_2_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		var store := get_node_or_null("/root/SessionStore") as PlayerSessionStore
		if store:
			store.preselected_exercise = "pinza"
		var session_game = load("res://session_game.tscn")
		if session_game:
			get_tree().change_scene_to_packed(session_game)

func _on_activity_3_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		var store := get_node_or_null("/root/SessionStore") as PlayerSessionStore
		if store:
			store.preselected_exercise = "coordinacion_3d"
		var session_game = load("res://session_game.tscn")
		if session_game:
			get_tree().change_scene_to_packed(session_game)

func _on_history_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		request_tab_change.emit(1)


