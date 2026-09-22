extends Control

## Pantalla de inicio de sesión de KINESIS.
## Conecta con ApiClient para autenticar contra la API en Azure.

@onready var input_user: LineEdit = %InputUser
@onready var input_pass: LineEdit = %InputPass
@onready var check_remember: CheckBox = %Check
@onready var btn_ingresar: Button = %BtnIngresar
@onready var error_label: Label = %ErrorLabel

var _is_submitting: bool = false


func _ready() -> void:
	btn_ingresar.pressed.connect(_on_ingresar_pressed)
	input_user.text_submitted.connect(func(_text): input_pass.grab_focus())
	input_pass.text_submitted.connect(func(_text): _on_ingresar_pressed())
	
	if has_node("/root/ApiClient"):
		var api := get_node("/root/ApiClient")
		api.login_succeeded.connect(_on_login_succeeded)
		api.login_failed.connect(_on_login_failed)
		
		# Si ya hay una sesión guardada y válida, navegar automáticamente al inicio
		if api.is_authenticated():
			_navigate_to_main()


func _on_ingresar_pressed() -> void:
	if _is_submitting:
		return
	
	var email := input_user.text.strip_edges()
	var password := input_pass.text
	
	if email.is_empty():
		_show_error("Por favor, ingresá tu correo electrónico.")
		input_user.grab_focus()
		return
	
	if password.is_empty():
		_show_error("Por favor, ingresá tu contraseña.")
		input_pass.grab_focus()
		return
	
	_set_loading(true)
	
	if has_node("/root/ApiClient"):
		var remember := check_remember.button_pressed if check_remember != null else true
		get_node("/root/ApiClient").login(email, password, remember)
	else:
		_set_loading(false)
		_show_error("Error interno: ApiClient no disponible.")


func _on_login_succeeded(_data: Dictionary) -> void:
	_set_loading(false)
	_navigate_to_main()


func _on_login_failed(error_message: String, _status_code: int) -> void:
	_set_loading(false)
	_show_error(error_message)


func _show_error(message: String) -> void:
	if error_label != null:
		error_label.text = message
		error_label.show()


func _set_loading(loading: bool) -> void:
	_is_submitting = loading
	btn_ingresar.disabled = loading
	btn_ingresar.text = "Ingresando..." if loading else "Ingresar"
	if loading and error_label != null:
		error_label.hide()


func _navigate_to_main() -> void:
	get_tree().change_scene_to_file("res://main_shell.tscn")
