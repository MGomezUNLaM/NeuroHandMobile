extends Control

## Pantalla de inicio de sesión de KINESIS.
## Conecta con ApiClient para autenticar contra la API en Azure.

@onready var input_user: LineEdit = %InputUser
@onready var input_pass: LineEdit = %InputPass
@onready var check_remember: CheckBox = %Check
@onready var btn_ingresar: Button = %BtnIngresar
@onready var error_label: Label = %ErrorLabel
@onready var btn_olvide: Button = %BtnOlvide

# Modal de recuperación de contraseña
@onready var forgot_modal: Control = %ForgotModal
@onready var input_forgot_email: LineEdit = %InputForgotEmail
@onready var forgot_status_label: Label = %ForgotStatusLabel
@onready var btn_send_forgot: Button = %BtnSendForgot
@onready var btn_cancel_forgot: Button = %BtnCancelForgot

var _is_submitting: bool = false


func _ready() -> void:
	btn_ingresar.pressed.connect(_on_ingresar_pressed)
	input_user.text_submitted.connect(func(_text): input_pass.grab_focus())
	input_pass.text_submitted.connect(func(_text): _on_ingresar_pressed())
	
	if btn_olvide != null:
		btn_olvide.pressed.connect(_on_olvide_pressed)
	if btn_send_forgot != null:
		btn_send_forgot.pressed.connect(_on_send_forgot_pressed)
	if btn_cancel_forgot != null:
		btn_cancel_forgot.pressed.connect(_on_cancel_forgot_pressed)
	if input_forgot_email != null:
		input_forgot_email.text_submitted.connect(func(_text): _on_send_forgot_pressed())
	
	if has_node("/root/ApiClient"):
		var api := get_node("/root/ApiClient")
		api.login_succeeded.connect(_on_login_succeeded)
		api.login_failed.connect(_on_login_failed)
		api.forgot_password_succeeded.connect(_on_forgot_succeeded)
		api.forgot_password_failed.connect(_on_forgot_failed)
		
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


# ── RECUPERACIÓN DE CONTRASEÑA ────────────────────────────────────────────────

func _on_olvide_pressed() -> void:
	if forgot_modal == null:
		return
	
	# Pre-llenar con el correo escrito en el login si existe
	if input_forgot_email != null:
		input_forgot_email.text = input_user.text.strip_edges()
	
	if forgot_status_label != null:
		forgot_status_label.hide()
	
	btn_send_forgot.disabled = false
	btn_send_forgot.text = "Enviar correo"
	forgot_modal.show()
	
	if input_forgot_email != null:
		input_forgot_email.grab_focus()


func _on_cancel_forgot_pressed() -> void:
	if forgot_modal != null:
		forgot_modal.hide()


func _on_send_forgot_pressed() -> void:
	var email := input_forgot_email.text.strip_edges()
	if email.is_empty():
		_show_forgot_status("Por favor, ingresá tu correo electrónico.", true)
		input_forgot_email.grab_focus()
		return
	
	if not email.contains("@") or not email.contains("."):
		_show_forgot_status("Ingresá un formato de correo electrónico válido.", true)
		input_forgot_email.grab_focus()
		return
	
	btn_send_forgot.disabled = true
	btn_send_forgot.text = "Enviando..."
	if forgot_status_label != null:
		forgot_status_label.hide()
	
	if has_node("/root/ApiClient"):
		get_node("/root/ApiClient").forgot_password(email)
	else:
		btn_send_forgot.disabled = false
		btn_send_forgot.text = "Enviar correo"
		_show_forgot_status("Error: servicio de red no disponible.", true)


func _on_forgot_succeeded(message: String) -> void:
	btn_send_forgot.disabled = true
	btn_send_forgot.text = "¡Correo enviado!"
	_show_forgot_status(message, false)


func _on_forgot_failed(error_message: String, _status_code: int) -> void:
	btn_send_forgot.disabled = false
	btn_send_forgot.text = "Enviar correo"
	_show_forgot_status(error_message, true)


func _show_forgot_status(message: String, is_error: bool) -> void:
	if forgot_status_label != null:
		forgot_status_label.text = message
		if is_error:
			forgot_status_label.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
		else:
			forgot_status_label.add_theme_color_override("font_color", Color(0.1, 0.65, 0.35, 1.0))
		forgot_status_label.show()
