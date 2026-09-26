extends Control

## Controlador del Dashboard principal (Mockup 1).
## Dispara la navegación hacia los desafíos, los logros o la gestión del guante.

signal navigate_to(view_index: int)

@onready var greeting_label: Label = %GreetingLabel
@onready var btn_desafios: Button = %BtnDesafios
@onready var btn_logros: Button = %BtnLogros
@onready var btn_guante: Button = %BtnGuante
@onready var btn_profile: Button = %BtnProfile


func _ready() -> void:
	btn_desafios.pressed.connect(_on_desafios_pressed)
	btn_logros.pressed.connect(_on_logros_pressed)
	btn_guante.pressed.connect(_on_guante_pressed)
	if btn_profile != null:
		btn_profile.pressed.connect(_on_profile_pressed)
	_update_greeting()


func on_view_activated() -> void:
	_update_greeting()


func _update_greeting() -> void:
	var name_to_show := "Paciente"
	if has_node("/root/ApiClient"):
		var api := get_node("/root/ApiClient")
		if api.first_name != "":
			name_to_show = api.first_name.capitalize()
		elif api.full_name != "":
			name_to_show = api.full_name.capitalize()
		elif api.user_email != "":
			var username: String = api.user_email.split("@")[0]
			name_to_show = username.replace(".", " ").capitalize()
		elif not api.current_user.is_empty():
			var prof: Variant = api.current_user.get("profile", {})
			if prof is Dictionary and prof.has("firstName") and str(prof.get("firstName", "")) != "":
				name_to_show = str(prof.get("firstName", "")).capitalize()
	
	greeting_label.text = "¡Bienvenido, %s!" % name_to_show


func _on_desafios_pressed() -> void:
	navigate_to.emit(1)


func _on_logros_pressed() -> void:
	navigate_to.emit(2)


func _on_guante_pressed() -> void:
	navigate_to.emit(3)


func _on_profile_pressed() -> void:
	navigate_to.emit(5)

