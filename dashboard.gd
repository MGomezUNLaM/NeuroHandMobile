extends Control

signal request_tab_change(index: int)

const DESIGN_SIZE := Vector2(1080.0, 2340.0)

@onready var _main_column: VBoxContainer = $MainColumn
@onready var btn_comenzar: Button = %BtnComenzar

func _ready() -> void:
	if btn_comenzar:
		btn_comenzar.pressed.connect(_on_start_pressed)
	
	await get_tree().process_frame

func _on_start_pressed() -> void:
	# Transición al juego de "Abrir y cerrar la mano"
	var session_game = load("res://session_game.tscn")
	if session_game:
		get_tree().change_scene_to_packed(session_game)


