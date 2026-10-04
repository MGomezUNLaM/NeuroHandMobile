extends Control

## Controlador del Dashboard principal (Home).
## Muestra el tratamiento activo, la sesión habilitada, métricas de racha/progreso y accesos directos.

signal navigate_to(view_index: int)

# Header
@onready var greeting_label: Label = %GreetingLabel
@onready var btn_avatar: Button = %BtnAvatar
@onready var btn_glove_pill: Button = %BtnGlovePill
@onready var glove_status_label: Label = %GloveStatusLabel

# Hero Card
@onready var treatment_title: Label = %TreatmentTitle
@onready var treatment_obj: Label = %TreatmentObj
@onready var therapist_tag: Label = %TherapistTag
@onready var session_status_label: Label = %SessionStatusLabel
@onready var session_sub_label: Label = %SessionSubLabel
@onready var btn_start_session: Button = %BtnStartSession

# Métricas
@onready var stat_streak_val: Label = %StatStreakVal
@onready var stat_time_val: Label = %StatTimeVal
@onready var stat_accuracy_val: Label = %StatAccuracyVal

# Accesos directos
@onready var btn_desafios: Button = %BtnDesafios
@onready var desafios_desc: Label = %DesafiosDesc
@onready var btn_guante: Button = %BtnGuante
@onready var btn_logros: Button = %BtnLogros


func _ready() -> void:
	if btn_avatar != null:
		btn_avatar.pressed.connect(func(): navigate_to.emit(5))
	btn_desafios.pressed.connect(func(): navigate_to.emit(1))
	btn_guante.pressed.connect(func(): navigate_to.emit(4))
	btn_logros.pressed.connect(func(): navigate_to.emit(2))
	btn_glove_pill.pressed.connect(func(): navigate_to.emit(3))
	btn_start_session.pressed.connect(_on_start_session_pressed)

	if has_node("/root/BleManager"):
		var ble = get_node("/root/BleManager")
		ble.connected.connect(func(_name = ""): _update_glove_status())
		ble.disconnected.connect(func(): _update_glove_status())
		ble.battery_updated.connect(func(_pct): _update_glove_status())

	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		api.treatment_fetched.connect(_on_treatment_fetched)
		api.treatments_fetched.connect(_on_treatments_fetched)
		if api.is_authenticated() and api.current_treatment.is_empty():
			api.get_treatment()

	_update_greeting()
	_update_treatment_info()
	_update_glove_status()
	_update_metrics()


func on_view_activated() -> void:
	_update_greeting()
	_update_treatment_info()
	_update_glove_status()
	_update_metrics()
	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		if api.is_authenticated() and api.current_treatment.is_empty():
			api.get_treatment()


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

	greeting_label.text = "¡Hola, %s!" % name_to_show


func _update_treatment_info() -> void:
	if not has_node("/root/ApiClient"):
		return
	var api = get_node("/root/ApiClient")
	var t: Dictionary = api.current_treatment
	if not t.is_empty():
		var t_name: String = str(t.get("name", "")).strip_edges()
		if t_name != "":
			treatment_title.text = t_name
		var t_obj: String = str(t.get("objective", "")).strip_edges()
		if t_obj != "":
			treatment_obj.text = t_obj

		var therapist: Dictionary = t.get("therapist", {})
		if not therapist.is_empty():
			var th_name := "%s %s" % [therapist.get("firstName", ""), therapist.get("lastName", "")]
			therapist_tag.text = "Terapeuta: %s" % th_name.strip_edges()

		# Sesiones
		var sessions: Array = t.get("sessions", [])
		if sessions.size() > 0:
			var s1: Dictionary = sessions[0]
			var s_order: int = int(s1.get("order", 1))
			var acts: Array = s1.get("sessionActivities", [])
			session_status_label.text = "● Sesión %d: Habilitada" % s_order
			session_sub_label.text = "%d ejercicios asignados para hoy" % acts.size()
			desafios_desc.text = "Sesión %d • %d ejercicios" % [s_order, acts.size()]
			return

	treatment_title.text = "Recuperación por esguince"
	treatment_obj.text = "Recuperar la movilidad de la muñeca y los dedos de la mano derecha."
	therapist_tag.text = "Terapeuta: Mario Perez"
	session_status_label.text = "● Sesión 1: Habilitada"
	session_sub_label.text = "2 ejercicios asignados"
	desafios_desc.text = "Explorar sesiones y ejercicios individuales"


func _update_metrics() -> void:
	stat_streak_val.text = "15 días"
	stat_time_val.text = "3h 35m"
	stat_accuracy_val.text = "94%"


func _on_treatment_fetched(_treatment: Dictionary) -> void:
	_update_treatment_info()


func _on_treatments_fetched(_treatments: Array) -> void:
	_update_treatment_info()


func _update_glove_status() -> void:
	if glove_status_label == null:
		return
	if has_node("/root/BleManager"):
		var ble = get_node("/root/BleManager")
		if ble.is_connected:
			var bat: int = int(ble.battery_level)
			if bat <= 20:
				glove_status_label.text = "🧤 Conectado • ⚠️ %d%%" % bat
				glove_status_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.10, 1.0))
			else:
				glove_status_label.text = "🧤 Conectado • 🔋 %d%%" % bat
				glove_status_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
			return
	glove_status_label.text = "⚪ Conectar Guante"
	glove_status_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.55, 1.0))


func _on_start_session_pressed() -> void:
	# Navegar a la vista de Desafíos / Sesiones dentro del Shell principal
	navigate_to.emit(1)
