extends Control

## Pantalla de Perfil de Paciente (KINESIS).
## Consulta y actualiza los datos del paciente mediante GET y PATCH /api/patients/:id.
## Alterna entre un modo de lectura (con datos destacados en negrita y negro nítido)
## y un modo de edición con botones de Guardar cambios y Cancelar.

signal navigate_to(view_index: int)
signal request_tab_change(index: int)

# Header
@onready var header_name: Label = %HeaderName
@onready var header_email: Label = %HeaderEmail
@onready var avatar_initial: Label = %AvatarInitial
@onready var status_badge: Label = %StatusBadge

# Contenedores de Modo
@onready var view_container: Control = %ViewContainer
@onready var edit_container: Control = %EditContainer

# Modo Lectura
@onready var view_first_name: Label = %ViewFirstName
@onready var view_last_name: Label = %ViewLastName
@onready var view_email: Label = %ViewEmail
@onready var view_doc: Label = %ViewDoc
@onready var view_phone: Label = %ViewPhone
@onready var view_birth_date: Label = %ViewBirthDate
@onready var btn_edit_profile: Button = %BtnEditProfile
@onready var btn_logout: Button = %BtnLogout

# Modo Edición
@onready var input_first_name: LineEdit = %InputFirstName
@onready var input_last_name: LineEdit = %InputLastName
@onready var input_email: LineEdit = %InputEmail
@onready var option_doc_type: OptionButton = %OptionDocType
@onready var input_doc_number: LineEdit = %InputDocNumber
@onready var input_phone: LineEdit = %InputPhone
@onready var input_birth_date: LineEdit = %InputBirthDate
@onready var btn_save: Button = %BtnSave
@onready var btn_cancel: Button = %BtnCancel

# Navegación y Feedback
@onready var status_label: Label = %StatusLabel
@onready var btn_back: Button = %BtnBack

var _cached_data: Dictionary = {}
var _is_editing: bool = false


func _ready() -> void:
	if btn_back != null:
		btn_back.pressed.connect(_on_back_pressed)
	if btn_edit_profile != null:
		btn_edit_profile.pressed.connect(_on_edit_pressed)
	if btn_logout != null:
		btn_logout.pressed.connect(_on_logout_pressed)
	if btn_save != null:
		btn_save.pressed.connect(_on_save_pressed)
	if btn_cancel != null:
		btn_cancel.pressed.connect(_on_cancel_pressed)
	
	_setup_doc_types()
	_set_edit_mode(false)
	
	if has_node("/root/ApiClient"):
		var api := get_node("/root/ApiClient")
		api.patient_fetched.connect(_on_patient_fetched)
		api.patient_fetch_failed.connect(_on_patient_fetch_failed)
		api.patient_updated.connect(_on_patient_updated)
		api.patient_update_failed.connect(_on_patient_update_failed)
	
	load_profile()


func on_view_activated() -> void:
	_set_edit_mode(false)
	load_profile()


func _setup_doc_types() -> void:
	if option_doc_type == null:
		return
	option_doc_type.clear()
	option_doc_type.add_item("DNI", 0)
	option_doc_type.add_item("PASAPORTE", 1)
	option_doc_type.add_item("OTRO", 2)


func _set_edit_mode(is_editing: bool) -> void:
	_is_editing = is_editing
	if view_container != null:
		view_container.visible = not is_editing
	if edit_container != null:
		edit_container.visible = is_editing
	if status_label != null:
		status_label.hide()
	
	if is_editing and input_first_name != null:
		input_first_name.grab_focus()


func load_profile() -> void:
	if status_label != null:
		status_label.hide()
	
	if has_node("/root/ApiClient"):
		var api := get_node("/root/ApiClient")
		_populate_from_api_memory(api)
		api.get_patient_profile()


func _populate_from_api_memory(api: Node) -> void:
	if not api.current_patient.is_empty():
		_populate_data(api.current_patient)
	else:
		var fallback_data := {
			"firstName": api.first_name,
			"lastName": api.last_name,
			"user": {
				"email": api.user_email,
				"status": api.user_status
			}
		}
		_populate_data(fallback_data)


func _populate_data(data: Dictionary) -> void:
	_cached_data = data
	
	var f_name := str(data.get("firstName", "")).strip_edges()
	var l_name := str(data.get("lastName", "")).strip_edges()
	var doc_num := str(data.get("documentNumber", "")).strip_edges()
	var phone := str(data.get("phone", "")).strip_edges()
	var b_date := str(data.get("birthDate", "")).strip_edges()
	if b_date.contains("T"):
		b_date = b_date.split("T")[0]
	
	var email := ""
	var status := ""
	if data.has("user") and data["user"] is Dictionary:
		email = str(data["user"].get("email", "")).strip_edges()
		status = str(data["user"].get("status", "")).strip_edges()
	
	if email == "" and has_node("/root/ApiClient"):
		email = get_node("/root/ApiClient").user_email
	if status == "" and has_node("/root/ApiClient"):
		status = get_node("/root/ApiClient").user_status
	
	var doc_type := str(data.get("documentType", "DNI")).to_upper()
	if doc_type.is_empty():
		doc_type = "DNI"
	
	# 1. Modo Lectura: etiquetas en negrita y negro nítido
	if view_first_name != null:
		view_first_name.text = f_name if not f_name.is_empty() else "-"
	if view_last_name != null:
		view_last_name.text = l_name if not l_name.is_empty() else "-"
	if view_email != null:
		view_email.text = email if not email.is_empty() else "-"
	if view_doc != null:
		if not doc_num.is_empty():
			view_doc.text = "%s %s" % [doc_type, doc_num]
		else:
			view_doc.text = "No especificado"
	if view_phone != null:
		view_phone.text = phone if not phone.is_empty() else "No especificado"
	if view_birth_date != null:
		view_birth_date.text = b_date if not b_date.is_empty() else "No especificada"
	
	# 2. Modo Edición: inputs del formulario
	if input_first_name != null:
		input_first_name.text = f_name
	if input_last_name != null:
		input_last_name.text = l_name
	if input_email != null:
		input_email.text = email
	if input_doc_number != null:
		input_doc_number.text = doc_num
	if input_phone != null:
		input_phone.text = phone
	if input_birth_date != null:
		input_birth_date.text = b_date
	
	if option_doc_type != null:
		match doc_type:
			"PASAPORTE":
				option_doc_type.select(1)
			"OTRO":
				option_doc_type.select(2)
			_:
				option_doc_type.select(0)
	
	# 3. Cabecera
	_update_header(f_name, l_name, email, status)


func _update_header(f_name: String, l_name: String, email: String, status: String) -> void:
	var full := ("%s %s" % [f_name, l_name]).strip_edges()
	if full.is_empty():
		full = "Paciente"
	
	if header_name != null:
		header_name.text = full
	if header_email != null:
		header_email.text = email if not email.is_empty() else "paciente@ejemplo.com"
	if avatar_initial != null:
		avatar_initial.text = f_name.left(1).to_upper() if not f_name.is_empty() else "P"
	if status_badge != null:
		var st := status.to_upper() if not status.is_empty() else "ACTIVO"
		status_badge.text = "Estado: %s" % st


func _on_edit_pressed() -> void:
	_populate_data(_cached_data)
	_set_edit_mode(true)


func _on_cancel_pressed() -> void:
	_populate_data(_cached_data)
	_set_edit_mode(false)


func _on_save_pressed() -> void:
	var f_name := input_first_name.text.strip_edges()
	var l_name := input_last_name.text.strip_edges()
	var email := input_email.text.strip_edges()
	var doc_num := input_doc_number.text.strip_edges()
	var phone := input_phone.text.strip_edges()
	var b_date := input_birth_date.text.strip_edges()
	var doc_type := "DNI"
	if option_doc_type != null:
		doc_type = option_doc_type.get_item_text(option_doc_type.selected)
	
	if f_name.is_empty() or l_name.is_empty():
		_show_status("Por favor, ingresá tu nombre y apellido.", true)
		return
	
	if email.is_empty() or not email.contains("@"):
		_show_status("Por favor, ingresá un correo electrónico válido.", true)
		return
	
	var payload: Dictionary = {
		"firstName": f_name,
		"lastName": l_name,
		"email": email,
		"documentType": doc_type,
		"documentNumber": doc_num,
		"phone": phone,
		"birthDate": b_date
	}
	
	btn_save.disabled = true
	btn_cancel.disabled = true
	btn_save.text = "Guardando..."
	if status_label != null:
		status_label.hide()
	
	if has_node("/root/ApiClient"):
		get_node("/root/ApiClient").update_patient_profile(payload)
	else:
		btn_save.disabled = false
		btn_cancel.disabled = false
		btn_save.text = "Guardar cambios"
		_show_status("Error: servicio de red no disponible.", true)


func _on_patient_fetched(data: Dictionary) -> void:
	_populate_data(data)


func _on_patient_fetch_failed(error_message: String, _status_code: int) -> void:
	_show_status(error_message, true)


func _on_patient_updated(data: Dictionary) -> void:
	btn_save.disabled = false
	btn_cancel.disabled = false
	btn_save.text = "Guardar cambios"
	_populate_data(data)
	_set_edit_mode(false)
	_show_status("¡Perfil actualizado con éxito!", false)


func _on_patient_update_failed(error_message: String, _status_code: int) -> void:
	btn_save.disabled = false
	btn_cancel.disabled = false
	btn_save.text = "Guardar cambios"
	_show_status(error_message, true)


func _show_status(message: String, is_error: bool) -> void:
	if status_label != null:
		status_label.text = message
		if is_error:
			status_label.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
		else:
			status_label.add_theme_color_override("font_color", Color(0.1, 0.65, 0.35, 1.0))
		status_label.show()


func _on_logout_pressed() -> void:
	if has_node("/root/ApiClient"):
		get_node("/root/ApiClient").logout()
	get_tree().change_scene_to_file("res://login.tscn")


func _on_back_pressed() -> void:
	if _is_editing:
		_on_cancel_pressed()
	else:
		navigate_to.emit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
