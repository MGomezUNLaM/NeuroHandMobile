extends Control

@onready var btn_ingresar: Button = %BtnIngresar

func _ready() -> void:
	btn_ingresar.pressed.connect(_on_ingresar_pressed)

func _on_ingresar_pressed() -> void:
	# Por ahora, simplemente transicionamos a main_shell
	get_tree().change_scene_to_file("res://main_shell.tscn")
