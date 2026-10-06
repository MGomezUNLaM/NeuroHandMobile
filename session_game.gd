extends Control

signal navigate_to(view_index: int)

var session_duration := 30.0
const GAME_SCENE := "res://session_game.tscn"
const DASHBOARD_SCENE := "res://main_shell.tscn"

enum Phase { READY, INSTRUCTION, PLAYING, FINISHED }
enum MenuScreen { TREATMENTS, SESSIONS, GAMES, NONE }

var _phase := Phase.READY
var _current_menu_screen := MenuScreen.TREATMENTS
var _time_left := 30.0
var _taps := 0
var _glove_connected := false

var _minigame_instance: Node = null
var _selected_game_scene: String = ""
var _instruction_overlay: Node = null
var _current_exercise_type: String = "flexion"
var _current_difficulty_name: String = "medio"
var _current_difficulty_factor: float = 1.0
var _session_activity_id: String = ""
var _started_at_iso: String = ""
var _measurements: Array[Dictionary] = []
var _sample_timer: float = 0.0
const SAMPLE_INTERVAL: float = 0.05 # 20Hz (50ms)

# Datos de navegación jerárquica
var _selected_treatment: Dictionary = {}
var _selected_session: Dictionary = {}
var _is_functional_selected: bool = false
var _instruction_text: String = ""

# Estilos y tipografías para tarjetas dinámicas
var _style_card: StyleBoxFlat
var _style_card_hover: StyleBoxFlat
var _style_card_pressed: StyleBoxFlat
var _style_card_disabled: StyleBoxFlat
var _style_pill_active: StyleBoxFlat
var _style_pill_disabled: StyleBoxFlat
var _font_bold: SystemFont
var _font_semibold: SystemFont

# ── Nodos de Navegación Jerárquica ──────────────────────────────────────────
@onready var _treatments_menu: ColorRect = %TreatmentsMenu
@onready var _treatments_list: VBoxContainer = %TreatmentsList
@onready var _btn_back_treatments: Button = %BtnBackTreatments

@onready var _sessions_menu: ColorRect = %SessionsMenu
@onready var _sessions_list: VBoxContainer = %SessionsList
@onready var _btn_back_sessions: Button = %BtnBackSessions
@onready var _sessions_header_title: Label = %SessionsHeaderTitle
@onready var _sessions_header_subtitle: Label = %SessionsHeaderSubtitle

@onready var _game_selection_menu: ColorRect = %GameSelectionMenu
@onready var _btn_back_games: Button = %BtnBackGames
@onready var _session_title_label: Label = %SessionTitleLabel
@onready var _session_subtitle_label: Label = %SessionSubtitleLabel
@onready var _session_diff_badge: Label = %SessionDiffBadge

# ── Nodos de Juego / HUD ─────────────────────────────────────────────────────
@onready var _tap_zone: ColorRect = %TapZone
@onready var _timer_label: Label = %TimerLabel
@onready var _taps_label: Label = %TapsLabelOld
@onready var _instruction_image: TextureRect = %InstructionImage
@onready var _instruction_label: Label = %InstructionLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _results_panel: PanelContainer = %ResultsPanel
@onready var _results_title: Label = %ResultsTitle
@onready var _results_detail: Label = %ResultsDetail
@onready var _mascot: TextureRect = %MascotBackdrop
@onready var _tap_flash: ColorRect = %TapFlash

# ── Nodos BLE / Flex ─────────────────────────────────────────────────────────
@onready var _flex_detector: FlexTapDetector = %FlexTapDetector
@onready var _flex_bar: ProgressBar = %FlexBar
@onready var _flex_label: Label = %FlexLabel
@onready var _ble_status_label: Label = %BleStatusLabel
@onready var _flex_panel: PanelContainer = %FlexPanel

var _ble_manager: Node = null

func _get_api_client():
	if is_inside_tree() and get_tree() != null and get_tree().root.has_node("ApiClient"):
		return get_tree().root.get_node("ApiClient")
	return null


func _get_session_store() -> PlayerSessionStore:
	if is_inside_tree() and get_tree() != null and get_tree().root.has_node("SessionStore"):
		return get_tree().root.get_node("SessionStore") as PlayerSessionStore
	return null


func _get_ble_manager():
	if is_inside_tree() and get_tree() != null and get_tree().root.has_node("BleManager"):
		return get_tree().root.get_node("BleManager")
	return null


func _ready() -> void:
	_init_styles()
	_init_fonts()

	# Conectar botones de retroceso entre pantallas del árbol
	if _btn_back_treatments != null and not _btn_back_treatments.pressed.is_connected(_on_back_to_dashboard):
		_btn_back_treatments.pressed.connect(_on_back_to_dashboard)
	if _btn_back_sessions != null and not _btn_back_sessions.pressed.is_connected(_on_back_to_treatments):
		_btn_back_sessions.pressed.connect(_on_back_to_treatments)
	if _btn_back_games != null and not _btn_back_games.pressed.is_connected(_on_back_to_sessions):
		_btn_back_games.pressed.connect(_on_back_to_sessions)

	if has_node("%BtnExitGame"):
		var btn_exit = get_node("%BtnExitGame") as Button
		if btn_exit != null and not btn_exit.pressed.is_connected(_abort_current_game):
			btn_exit.pressed.connect(_abort_current_game)
		btn_exit.hide()

	_results_panel.hide()
	if not _tap_zone.gui_input.is_connected(_on_tap_zone_input):
		_tap_zone.gui_input.connect(_on_tap_zone_input)
	
	if has_node("%StartGameButton"):
		%StartGameButton.hide()
		if not %StartGameButton.pressed.is_connected(_on_start_button_pressed):
			%StartGameButton.pressed.connect(_on_start_button_pressed)

	# Inicializar BLE
	_setup_ble()

	_reset_hud()
	_start_mascot_idle()
	
	# Verificar si viene con actividad preseleccionada desde otra vista (ej. misiones directas)
	var store: PlayerSessionStore = _get_session_store()
	if store != null and store.preselected_exercise != "":
		_show_menu_screen(MenuScreen.NONE)
		var pre: String = store.preselected_exercise
		_current_difficulty_name = store.preselected_difficulty
		_current_difficulty_factor = store.preselected_difficulty_factor
		_session_activity_id = store.preselected_activity_id
		store.preselected_exercise = ""
		store.preselected_activity_id = ""
		match pre:
			"pinza":
				_on_pinch_selected()
			"coordinacion_3d", "basket":
				_on_basket_selected()
			"flexion_constante", "botella":
				_on_functional_selected()
			"flexion", "flappy":
				_on_arcade_selected()
	else:
		# Flujo estándar: Nivel 1 (Tratamientos) -> Nivel 2 (Sesiones) -> Nivel 3 (Juegos)
		_show_menu_screen(MenuScreen.TREATMENTS)
		_load_treatments()


func _init_styles() -> void:
	_style_card = StyleBoxFlat.new()
	_style_card.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	_style_card.set_corner_radius_all(22)
	_style_card.set_border_width_all(2)
	_style_card.border_color = Color(0.88, 0.95, 0.92, 1.0)
	_style_card.content_margin_left = 20
	_style_card.content_margin_top = 16
	_style_card.content_margin_right = 20
	_style_card.content_margin_bottom = 16
	
	_style_card_hover = _style_card.duplicate()
	_style_card_hover.border_color = Color(0.118, 0.596, 0.647, 1.0)
	_style_card_hover.bg_color = Color(0.98, 0.995, 0.995, 1.0)
	
	_style_card_pressed = _style_card.duplicate()
	_style_card_pressed.border_color = Color(0.09, 0.48, 0.52, 1.0)
	_style_card_pressed.bg_color = Color(0.94, 0.97, 0.98, 1.0)
	
	_style_card_disabled = StyleBoxFlat.new()
	_style_card_disabled.bg_color = Color(0.94, 0.95, 0.96, 1.0)
	_style_card_disabled.set_corner_radius_all(22)
	_style_card_disabled.set_border_width_all(1)
	_style_card_disabled.border_color = Color(0.85, 0.88, 0.90, 1.0)
	_style_card_disabled.content_margin_left = 20
	_style_card_disabled.content_margin_top = 16
	_style_card_disabled.content_margin_right = 20
	_style_card_disabled.content_margin_bottom = 16
	
	_style_pill_active = StyleBoxFlat.new()
	_style_pill_active.bg_color = Color(0.88, 0.96, 0.92, 1.0)
	_style_pill_active.set_corner_radius_all(12)
	_style_pill_active.content_margin_left = 10
	_style_pill_active.content_margin_top = 4
	_style_pill_active.content_margin_right = 10
	_style_pill_active.content_margin_bottom = 4
	
	_style_pill_disabled = StyleBoxFlat.new()
	_style_pill_disabled.bg_color = Color(0.88, 0.90, 0.92, 1.0)
	_style_pill_disabled.set_corner_radius_all(12)
	_style_pill_disabled.content_margin_left = 10
	_style_pill_disabled.content_margin_top = 4
	_style_pill_disabled.content_margin_right = 10
	_style_pill_disabled.content_margin_bottom = 4


func _init_fonts() -> void:
	_font_bold = SystemFont.new()
	_font_bold.font_names = PackedStringArray(["Sans-Serif"])
	_font_bold.font_weight = 700
	
	_font_semibold = SystemFont.new()
	_font_semibold.font_names = PackedStringArray(["Sans-Serif"])
	_font_semibold.font_weight = 600


func on_view_activated() -> void:
	# Al cambiar o volver a la pestaña de Desafíos, asegurarse de mostrar la pantalla de tratamientos si no hay juego en curso
	if _phase == Phase.READY or _phase == Phase.FINISHED:
		var store: PlayerSessionStore = _get_session_store()
		if store != null and store.preselected_exercise != "":
			return
		_load_treatments()


## Manejo jerárquico del botón atrás (usado por main_shell o Android)
## Retorna true si consumió el evento de atrás dentro del árbol jerárquico.
func handle_back_step() -> bool:
	if _current_menu_screen == MenuScreen.GAMES:
		_on_back_to_sessions()
		return true
	elif _current_menu_screen == MenuScreen.SESSIONS:
		_on_back_to_treatments()
		return true
	elif _phase == Phase.INSTRUCTION or _phase == Phase.READY and _current_menu_screen == MenuScreen.NONE:
		_abort_current_game()
		return true
	return false


# ── Navegación del Árbol (Tratamientos -> Sesiones -> Juegos) ──────────────

func _show_menu_screen(screen: MenuScreen) -> void:
	_current_menu_screen = screen
	if _treatments_menu:
		_treatments_menu.visible = (screen == MenuScreen.TREATMENTS)
	if _sessions_menu:
		_sessions_menu.visible = (screen == MenuScreen.SESSIONS)
	if _game_selection_menu:
		_game_selection_menu.visible = (screen == MenuScreen.GAMES)


func _on_back_to_dashboard() -> void:
	if navigate_to.get_connections().size() > 0:
		navigate_to.emit(0)
	else:
		get_tree().change_scene_to_file(DASHBOARD_SCENE)


func _on_back_to_treatments() -> void:
	_show_menu_screen(MenuScreen.TREATMENTS)


func _on_back_to_sessions() -> void:
	if not _selected_treatment.is_empty():
		_show_sessions_view(_selected_treatment)
	else:
		_show_menu_screen(MenuScreen.TREATMENTS)


func _load_treatments() -> void:
	var list: Array = []
	var api = _get_api_client()
	if api != null:
		if not api.treatments_fetched.is_connected(_on_treatments_fetched):
			api.treatments_fetched.connect(_on_treatments_fetched)
		if not api.treatment_fetched.is_connected(_on_single_treatment_fetched):
			api.treatment_fetched.connect(_on_single_treatment_fetched)
		list = api.get_patient_treatments()
		if api.is_authenticated() and api.patient_treatments.is_empty():
			api.get_treatment()
	else:
		list = _get_default_fallback_treatments()
	
	if list.is_empty():
		list = _get_default_fallback_treatments()
	
	_populate_treatments_list(list)


func _get_default_fallback_treatments() -> Array:
	if _get_api_client() != null:
		var api = _get_api_client()
		return api.get_fallback_treatments()
	
	var now_dict := Time.get_date_dict_from_system()
	var y: int = now_dict["year"]
	var m: int = now_dict["month"]
	var d: int = now_dict["day"]
	var today_str := "%04d-%02d-%02d" % [y, m, d]
	var next_m := m + 1 if m < 12 else 1
	var next_y := y if m < 12 else y + 1
	var prev_m := m - 1 if m > 1 else 12
	var prev_y := y if m > 1 else y - 1
	var future_str := "%04d-%02d-%02d" % [next_y, next_m, d]
	var past_str := "%04d-%02d-%02d" % [prev_y, prev_m, d]
	
	return [
		{
			"id": "t-demo-01",
			"name": "Plan de Rehabilitación Motora",
			"description": "Tratamiento de movilidad articular, flexión de dedos y fuerza de agarre.",
			"startDate": today_str,
			"endDate": future_str,
			"therapist": { "name": "Lic. Kinesiología" },
			"sessions": [
				{
					"id": "s-demo-01",
					"name": "Sesión 1: Flexión y Agarre",
					"difficulty": "medio",
					"startDate": today_str,
					"endDate": future_str,
					"sessionActivities": [
						{
							"id": "sa-1",
							"name": "Flappy Bird",
							"type": "flexion",
							"difficulty": "medio"
						},
						{
							"id": "sa-2",
							"name": "Alcanza la Botella (3D)",
							"type": "flexion_constante",
							"difficulty": "medio"
						}
					]
				},
				{
					"id": "s-demo-02",
					"name": "Sesión 2: Coordinación y Pinza",
					"difficulty": "alto",
					"startDate": future_str,
					"endDate": future_str,
					"sessionActivities": [
						{
							"id": "sa-3",
							"name": "Pinza Fina (Piano)",
							"type": "pinza",
							"difficulty": "alto"
						}
					]
				},
				{
					"id": "s-demo-03",
					"name": "Sesión Inicial: Diagnóstico",
					"difficulty": "bajo",
					"startDate": past_str,
					"endDate": past_str,
					"sessionActivities": []
				}
			]
		}
	]


func _on_treatments_fetched(treatments: Array) -> void:
	if _current_menu_screen == MenuScreen.TREATMENTS:
		_populate_treatments_list(treatments)
	elif _current_menu_screen == MenuScreen.SESSIONS and not _selected_treatment.is_empty():
		var sel_id: String = str(_selected_treatment.get("id", ""))
		for t in treatments:
			if str(t.get("id", "")) == sel_id:
				_selected_treatment = t
				_populate_sessions_list(t)
				break


func _on_single_treatment_fetched(_t: Dictionary) -> void:
	if _current_menu_screen == MenuScreen.TREATMENTS and _get_api_client() != null:
		var api = _get_api_client()
		_populate_treatments_list(api.get_patient_treatments())


func _populate_treatments_list(treatments: Array) -> void:
	if _treatments_list == null:
		return
	for child in _treatments_list.get_children():
		_treatments_list.remove_child(child)
		child.queue_free()
	
	if treatments.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No tenés tratamientos activos registrados en este momento."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 1.0))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_treatments_list.add_child(empty_lbl)
		return
	
	for t_variant in treatments:
		if not (t_variant is Dictionary):
			continue
		var treatment: Dictionary = t_variant
		var card := _create_treatment_card(treatment)
		_treatments_list.add_child(card)
	
	# Tarjeta de apoyo y recordatorio terapéutico para llenar armónicamente el espacio
	var tip_card := _create_treatment_support_card()
	_treatments_list.add_child(tip_card)
	
	var elastic_spacer := Control.new()
	elastic_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_treatments_list.add_child(elastic_spacer)


func _create_treatment_support_card() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 150)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.94, 0.97, 0.98, 1.0)
	st.border_color = Color(0.85, 0.92, 0.94, 1.0)
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.set_corner_radius_all(20)
	st.content_margin_left = 20
	st.content_margin_top = 18
	st.content_margin_right = 20
	st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(header_hbox)
	
	var icon_lbl := Label.new()
	icon_lbl.text = "💡"
	icon_lbl.add_theme_font_size_override("font_size", 20)
	header_hbox.add_child(icon_lbl)
	
	var title_lbl := Label.new()
	title_lbl.text = "Recomendaciones de Terapia"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.067, 0.157, 0.235, 1.0))
	title_lbl.add_theme_font_override("font", _font_bold)
	header_hbox.add_child(title_lbl)
	
	var tip_text := Label.new()
	tip_text.text = "Completá al menos una sesión por día para mantener la racha activa y mejorar la movilidad de tu mano. Asegurate de calibrar el guante antes de comenzar los desafíos."
	tip_text.add_theme_font_size_override("font_size", 13)
	tip_text.add_theme_color_override("font_color", Color(0.40, 0.50, 0.55, 1.0))
	tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tip_text)
	
	return panel


func _create_treatment_card(treatment: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 180)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _style_card)
	btn.add_theme_stylebox_override("hover", _style_card_hover)
	btn.add_theme_stylebox_override("pressed", _style_card_pressed)
	btn.flat = false
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	btn.add_child(margin)
	
	var vbox_card := VBoxContainer.new()
	vbox_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_card.add_theme_constant_override("separation", 14)
	margin.add_child(vbox_card)
	
	var hbox_top := HBoxContainer.new()
	hbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_top.add_theme_constant_override("separation", 16)
	hbox_top.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox_card.add_child(hbox_top)
	
	# Icono decorativo de tratamiento
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(64, 64)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.88, 0.95, 0.96, 1.0)
	icon_style.set_corner_radius_all(32)
	icon_box.add_theme_stylebox_override("panel", icon_style)
	
	var icon_lbl := Label.new()
	icon_lbl.text = "📋"
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 30)
	icon_box.add_child(icon_lbl)
	hbox_top.add_child(icon_box)
	
	# Textos informativos
	var vbox_info := VBoxContainer.new()
	vbox_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_info.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox_info.add_theme_constant_override("separation", 4)
	hbox_top.add_child(vbox_info)
	
	var name_str: String = str(treatment.get("name", "Tratamiento de Rehabilitación"))
	var title_lbl := Label.new()
	title_lbl.text = name_str
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.067, 0.157, 0.235, 1.0))
	title_lbl.add_theme_font_override("font", _font_bold)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox_info.add_child(title_lbl)
	
	var desc_str: String = ""
	if treatment.has("therapist") and treatment["therapist"] is Dictionary:
		desc_str = str(treatment["therapist"].get("name", ""))
	if desc_str == "":
		desc_str = str(treatment.get("description", ""))
	if desc_str == "":
		desc_str = "Plan personalizado de ejercicios"
	
	var desc_lbl := Label.new()
	desc_lbl.text = desc_str
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.add_theme_font_size_override("font_size", 17)
	desc_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.48, 1.0))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.max_lines_visible = 2
	vbox_info.add_child(desc_lbl)
	
	# Flecha derecha
	var arrow_lbl := Label.new()
	arrow_lbl.text = "›"
	arrow_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_lbl.add_theme_font_size_override("font_size", 36)
	arrow_lbl.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
	arrow_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox_top.add_child(arrow_lbl)
	
	# Fila inferior: Estado de progreso y badge de sesiones
	var sessions_list: Array = _get_treatment_sessions(treatment)
	var bottom_row := HBoxContainer.new()
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_row.add_theme_constant_override("separation", 12)
	vbox_card.add_child(bottom_row)
	
	var progress_bar := ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.custom_minimum_size = Vector2(0, 14)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 33.0
	progress_bar.show_percentage = false
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.92, 0.94, 0.96, 1.0)
	pb_bg.set_corner_radius_all(7)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.118, 0.596, 0.647, 1.0)
	pb_fill.set_corner_radius_all(7)
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	progress_bar.add_theme_stylebox_override("fill", pb_fill)
	bottom_row.add_child(progress_bar)
	
	var sess_count_lbl := Label.new()
	sess_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sess_count_lbl.text = "%d %s disponibles" % [sessions_list.size(), "sesión" if sessions_list.size() == 1 else "sesiones"]
	sess_count_lbl.add_theme_font_size_override("font_size", 16)
	sess_count_lbl.add_theme_font_override("font", _font_semibold)
	sess_count_lbl.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
	bottom_row.add_child(sess_count_lbl)
	
	btn.pressed.connect(func(): _on_treatment_selected(treatment))
	return btn


func _get_treatment_sessions(treatment: Dictionary) -> Array:
	if treatment.has("sessions") and treatment["sessions"] is Array:
		return treatment["sessions"]
	if treatment.has("sesiones") and treatment["sesiones"] is Array:
		return treatment["sesiones"]
	if treatment.has("treatmentSessions") and treatment["treatmentSessions"] is Array:
		return treatment["treatmentSessions"]
	return []


func _on_treatment_selected(treatment: Dictionary) -> void:
	_selected_treatment = treatment
	if _get_api_client() != null:
		var api = _get_api_client()
		api.selected_treatment = treatment
	_show_sessions_view(treatment)


func _show_sessions_view(treatment: Dictionary) -> void:
	_show_menu_screen(MenuScreen.SESSIONS)
	
	var t_name: String = str(treatment.get("name", "Tratamiento"))
	_sessions_header_title.text = "Tratamiento: %s" % t_name
	_sessions_header_subtitle.text = "Sesiones del tratamiento • Seleccioná la sesión a realizar"
	
	_populate_sessions_list(treatment)


func _populate_sessions_list(treatment: Dictionary) -> void:
	if _sessions_list == null:
		return
	for child in _sessions_list.get_children():
		_sessions_list.remove_child(child)
		child.queue_free()
	
	var sessions: Array = _get_treatment_sessions(treatment)
	if sessions.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Este tratamiento aún no tiene sesiones registradas."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 1.0))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sessions_list.add_child(empty_lbl)
		return
	
	var api = _get_api_client()
	for session_variant in sessions:
		if not (session_variant is Dictionary):
			continue
		var session: Dictionary = session_variant
		var card := _create_session_card(session, api, sessions)
		_sessions_list.add_child(card)


func _create_session_card(session: Dictionary, api, all_sessions: Array = []) -> Control:
	var is_active := true
	var status_text := "DISPONIBLE"
	var date_text := ""
	
	if api != null:
		var timing: Dictionary = api.get_session_timing_info(session, all_sessions)
		is_active = timing.get("is_active", true)
		status_text = timing.get("status_label", "DISPONIBLE")
		date_text = timing.get("date_text", "")
	else:
		var timing: Dictionary = _calculate_session_timing_fallback(session, all_sessions)
		is_active = timing.get("is_active", true)
		status_text = timing.get("status_label", "DISPONIBLE")
		date_text = timing.get("date_text", "")
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 160)
	
	if is_active:
		btn.disabled = false
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_stylebox_override("normal", _style_card)
		btn.add_theme_stylebox_override("hover", _style_card_hover)
		btn.add_theme_stylebox_override("pressed", _style_card_pressed)
	else:
		btn.disabled = true
		btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		btn.add_theme_stylebox_override("disabled", _style_card_disabled)
		btn.add_theme_stylebox_override("normal", _style_card_disabled)
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	btn.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Fila superior: Badge de estado (DISPONIBLE o NO DISPONIBLE) y Flecha/Candado
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)
	
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _style_pill_active if is_active else _style_pill_disabled)
	
	var pill_lbl := Label.new()
	pill_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_lbl.add_theme_font_size_override("font_size", 16)
	pill_lbl.add_theme_font_override("font", _font_bold)
	if is_active:
		pill_lbl.text = "🟢 DISPONIBLE"
		pill_lbl.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
	else:
		pill_lbl.text = "🔒 " + status_text
		pill_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.53, 1.0))
	pill.add_child(pill_lbl)
	top_row.add_child(pill)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)
	
	var indicator_lbl := Label.new()
	indicator_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_active:
		indicator_lbl.text = "›"
		indicator_lbl.add_theme_font_size_override("font_size", 32)
		indicator_lbl.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
	else:
		indicator_lbl.text = "🔒"
		indicator_lbl.add_theme_font_size_override("font_size", 22)
		indicator_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.68, 1.0))
	top_row.add_child(indicator_lbl)
	
	# Título de la sesión
	var s_name: String = str(session.get("name", "Sesión de Ejercicios"))
	var title_lbl := Label.new()
	title_lbl.text = s_name
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_font_override("font", _font_bold)
	if is_active:
		title_lbl.add_theme_color_override("font_color", Color(0.067, 0.157, 0.235, 1.0))
	else:
		title_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.63, 1.0))
	vbox.add_child(title_lbl)
	
	# Fila de detalles: Fecha y Dificultad
	var details_row := HBoxContainer.new()
	details_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_row.add_theme_constant_override("separation", 14)
	vbox.add_child(details_row)
	
	var date_lbl := Label.new()
	date_lbl.text = "📅 " + (date_text if date_text != "" else "Fecha libre")
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_lbl.add_theme_font_size_override("font_size", 17)
	if is_active:
		date_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.48, 1.0))
	else:
		date_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.73, 1.0))
	details_row.add_child(date_lbl)
	
	var diff_str: String = str(session.get("difficulty", "medio")).capitalize()
	var diff_lbl := Label.new()
	diff_lbl.text = "• Dificultad: %s" % diff_str
	diff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diff_lbl.add_theme_font_size_override("font_size", 17)
	if is_active:
		diff_lbl.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
		diff_lbl.add_theme_font_override("font", _font_semibold)
	else:
		diff_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.73, 1.0))
	details_row.add_child(diff_lbl)
	
	# Conexión solo si la sesión está activa
	if is_active:
		btn.pressed.connect(func(): _on_session_selected(session))
	
	return btn


func _calculate_session_timing_fallback(session: Dictionary, all_sessions: Array = []) -> Dictionary:
	var start_val = session.get("startDate", session.get("fechaDesde", session.get("availableFrom", session.get("from", session.get("start_date", "")))))
	var end_val = session.get("endDate", session.get("fechaHasta", session.get("availableUntil", session.get("to", session.get("end_date", "")))))
	var s_str := str(start_val).strip_edges()
	var e_str := str(end_val).strip_edges()
	
	var s_disp := ""
	if s_str != "":
		var s_clean := s_str.split("T")[0] if s_str.contains("T") else s_str
		var p := s_clean.split("-")
		s_disp = "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else s_clean
		
	var e_disp := ""
	if e_str != "":
		var e_clean := e_str.split("T")[0] if e_str.contains("T") else e_str
		var p := e_clean.split("-")
		e_disp = "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else e_clean
	
	var date_text := ""
	if s_disp != "" and e_disp != "":
		date_text = "Del %s al %s" % [s_disp, e_disp]
	elif e_disp != "":
		date_text = "Hasta el %s" % e_disp
	elif s_disp != "":
		date_text = "Desde el %s" % s_disp
	else:
		date_text = "Siempre disponible"
	
	var status_raw := str(session.get("status", "")).strip_edges().to_upper()
	if status_raw in ["COMPLETED", "FINISHED", "DONE", "FINALIZADA"]:
		return {
			"is_active": false,
			"status_label": "FINALIZADA",
			"date_text": date_text
		}
	if status_raw in ["CANCELLED", "CANCELADA"]:
		return {
			"is_active": false,
			"status_label": "CANCELADA",
			"date_text": date_text
		}
	
	var now_dict := Time.get_date_dict_from_system()
	var today_str := "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]
	
	var s_ymd := s_str.split("T")[0] if s_str.contains("T") else s_str
	var e_ymd := e_str.split("T")[0] if e_str.contains("T") else e_str
	
	# 1. Si la fecha de inicio es estrictamente futura -> PRÓXIMAMENTE
	if s_ymd != "" and today_str < s_ymd:
		return {
			"is_active": false,
			"status_label": "PRÓXIMAMENTE",
			"date_text": date_text
		}
	
	# 2. Buscar si hay una sesión posterior en el tratamiento que ya haya comenzado
	var next_start := ""
	var curr_order: int = int(session.get("order", 0))
	
	for other in all_sessions:
		if not (other is Dictionary):
			continue
		var o_order: int = int(other.get("order", 0))
		var o_start_val = other.get("startDate", other.get("fechaDesde", other.get("availableFrom", other.get("from", other.get("start_date", "")))))
		var o_start := str(o_start_val).strip_edges()
		if o_start.contains("T"):
			o_start = o_start.split("T")[0]
		
		if curr_order > 0 and o_order > curr_order and o_start != "":
			if next_start == "" or o_start < next_start:
				next_start = o_start
		elif curr_order == 0 and o_start != "" and s_ymd != "" and o_start > s_ymd:
			if next_start == "" or o_start < next_start:
				next_start = o_start
	
	# Si una sesión posterior ya inició hoy o antes, la actual ya cumplió su ventana
	if next_start != "" and today_str >= next_start:
		return {
			"is_active": false,
			"status_label": "FINALIZADA",
			"date_text": date_text
		}
	
	# 3. Si no hay sesión posterior, verificar vigencia
	if e_ymd != "" and next_start == "":
		if today_str > e_ymd and status_raw not in ["PENDING", "ACTIVE"]:
			return {
				"is_active": false,
				"status_label": "FINALIZADA",
				"date_text": date_text
			}
	
	return {
		"is_active": true,
		"status_label": "DISPONIBLE",
		"date_text": date_text
	}


func _on_session_selected(session: Dictionary) -> void:
	_selected_session = session
	if _get_api_client() != null:
		var api = _get_api_client()
		api.selected_session = session
	
	_setup_game_selection_for_session(session)
	_show_menu_screen(MenuScreen.GAMES)


func _setup_game_selection_for_session(session: Dictionary) -> void:
	var s_name: String = str(session.get("name", "Sesión de Ejercicios"))
	_session_title_label.text = "Sesión: %s" % s_name
	_session_subtitle_label.text = "Actividades asignadas • Seleccioná una actividad para comenzar"
	var raw_diff: String = str(session.get("difficulty", "medio"))
	var diff_str: String = _translate_difficulty(raw_diff)
	_session_diff_badge.text = "Dificultad de la sesión: %s" % diff_str
	
	var arcade_btn = %GameSelectionMenu.find_child("ArcadeButton", true, false)
	var func_btn = %GameSelectionMenu.find_child("FunctionalButton", true, false)
	var pinch_btn = %GameSelectionMenu.find_child("PinchButton", true, false)
	var basket_btn = %GameSelectionMenu.find_child("BasketButton", true, false)
	
	var has_arcade: Dictionary = _find_activity_in_session(session, ["flappy", "flexion", "arcade", "pajaro", "bird"])
	var has_func: Dictionary = _find_activity_in_session(session, ["botella", "flexion_constante", "vaso", "bottle"])
	var has_pinch: Dictionary = _find_activity_in_session(session, ["pinza", "piano", "pinch"])
	var has_basket: Dictionary = _find_activity_in_session(session, ["basket", "coordinacion", "coordinacion_3d", "aro", "pelota"])
	
	var session_acts := _get_session_activities(session)
	var any_matched: bool = not has_arcade.is_empty() or not has_func.is_empty() or not has_pinch.is_empty() or not has_basket.is_empty()
	
	if not session_acts.is_empty() and any_matched:
		# Mostrar exclusivamente las actividades asignadas a esta sesión
		if arcade_btn:
			arcade_btn.visible = not has_arcade.is_empty()
			if arcade_btn.visible:
				_apply_diff_label(arcade_btn, has_arcade.get("difficulty", diff_str))
		if func_btn:
			func_btn.visible = not has_func.is_empty()
			if func_btn.visible:
				_apply_diff_label(func_btn, has_func.get("difficulty", diff_str))
		if pinch_btn:
			pinch_btn.visible = not has_pinch.is_empty()
			if pinch_btn.visible:
				_apply_diff_label(pinch_btn, has_pinch.get("difficulty", diff_str))
		if basket_btn:
			basket_btn.visible = not has_basket.is_empty()
			if basket_btn.visible:
				_apply_diff_label(basket_btn, has_basket.get("difficulty", diff_str))
	else:
		# Fallback: si la sesión no tiene actividades discriminadas, mostrar todos los juegos con la dificultad de la sesión
		if arcade_btn:
			arcade_btn.visible = true
			_apply_diff_label(arcade_btn, diff_str)
		if func_btn:
			func_btn.visible = true
			_apply_diff_label(func_btn, diff_str)
		if pinch_btn:
			pinch_btn.visible = true
			_apply_diff_label(pinch_btn, diff_str)
		if basket_btn:
			basket_btn.visible = true
			_apply_diff_label(basket_btn, diff_str)


func _get_session_activities(session: Dictionary) -> Array:
	if session.has("sessionActivities") and session["sessionActivities"] is Array:
		return session["sessionActivities"]
	if session.has("activities") and session["activities"] is Array:
		return session["activities"]
	if session.has("actividades") and session["actividades"] is Array:
		return session["actividades"]
	return []


func _find_activity_in_session(session: Dictionary, game_keys: Array) -> Dictionary:
	var acts := _get_session_activities(session)
	for a_item in acts:
		if not (a_item is Dictionary):
			continue
		var act_obj: Dictionary = a_item.get("activity", {}) if a_item.get("activity") is Dictionary else {}
		var game_obj: Dictionary = act_obj.get("game", {}) if act_obj.get("game") is Dictionary else {}
		
		var t_str: String = str(game_obj.get("id", act_obj.get("gameId", act_obj.get("type", a_item.get("type", ""))))).to_lower()
		var n_str: String = str(game_obj.get("name", act_obj.get("name", a_item.get("name", "")))).to_lower()
		
		for k in game_keys:
			var k_lower := str(k).to_lower()
			if t_str.contains(k_lower) or n_str.contains(k_lower):
				var act_diff: String = str(a_item.get("difficulty", session.get("difficulty", "medio"))).to_lower()
				var act_id: String = str(a_item.get("id", a_item.get("sessionActivityId", "")))
				return {
					"sessionActivityId": act_id,
					"id": act_id,
					"difficulty": act_diff,
					"difficulty_factor": _get_diff_factor(act_diff),
					"name": n_str,
					"raw": a_item
				}
	return {}


func _find_active_activity(game_keys: Array) -> Dictionary:
	if _get_api_client() == null:
		return {}
	var api = _get_api_client()
	for act in api.active_activities:
		var t: String = str(act.get("type", "")).to_lower()
		var n: String = str(act.get("name", "")).to_lower()
		for k in game_keys:
			var k_lower := str(k).to_lower()
			if t.contains(k_lower) or n.contains(k_lower):
				return act
	return {}


func _get_diff_factor(diff: String) -> float:
	match diff.to_lower():
		"bajo", "fácil", "facil", "easy":
			return 0.7
		"medio", "media", "medium":
			return 1.0
		"alto", "difícil", "dificil", "hard":
			return 1.3
		_:
			return 1.0


func _translate_difficulty(diff_str: String) -> String:
	match diff_str.strip_edges().to_lower():
		"low", "bajo", "baja", "facil", "fácil", "easy":
			return "Baja"
		"medium", "medio", "media", "med":
			return "Media"
		"high", "alto", "alta", "dificil", "difícil", "hard":
			return "Alta"
		_:
			return diff_str.capitalize()


func _apply_diff_label(btn: Control, diff_name: String) -> void:
	var label = btn.find_child("Title*", true, false)
	if label and label is Label:
		if label.text.contains("["):
			label.text = label.text.split("[")[0].strip_edges()
	
	var text_vbox = btn.find_child("TextVBox", true, false)
	if not text_vbox:
		return
	
	var translated := _translate_difficulty(diff_name)
	
	var badge = text_vbox.find_child("DiffBadge", true, false)
	if badge == null:
		badge = PanelContainer.new()
		badge.name = "DiffBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
		var b_margin = MarginContainer.new()
		b_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b_margin.add_theme_constant_override("margin_left", 8)
		b_margin.add_theme_constant_override("margin_right", 8)
		b_margin.add_theme_constant_override("margin_top", 2)
		b_margin.add_theme_constant_override("margin_bottom", 2)
		badge.add_child(b_margin)
		
		var b_label = Label.new()
		b_label.name = "DiffLabel"
		b_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b_label.add_theme_font_size_override("font_size", 11)
		b_label.add_theme_font_override("font", _font_bold)
		b_margin.add_child(b_label)
		
		text_vbox.add_child(badge)
		text_vbox.move_child(badge, 1)
	
	var b_lbl = badge.find_child("DiffLabel", true, false)
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	
	match translated:
		"Baja":
			style.bg_color = Color(0.88, 0.96, 0.90, 1.0)
			style.border_color = Color(0.4, 0.78, 0.5, 0.6)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			if b_lbl:
				b_lbl.text = "🟢 Dificultad: Baja"
				b_lbl.add_theme_color_override("font_color", Color(0.1, 0.5, 0.25, 1.0))
		"Media":
			style.bg_color = Color(0.99, 0.96, 0.85, 1.0)
			style.border_color = Color(0.85, 0.7, 0.2, 0.6)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			if b_lbl:
				b_lbl.text = "🟡 Dificultad: Media"
				b_lbl.add_theme_color_override("font_color", Color(0.65, 0.45, 0.05, 1.0))
		"Alta":
			style.bg_color = Color(0.99, 0.88, 0.88, 1.0)
			style.border_color = Color(0.85, 0.35, 0.35, 0.6)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			if b_lbl:
				b_lbl.text = "🔴 Dificultad: Alta"
				b_lbl.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0))
		_:
			style.bg_color = Color(0.93, 0.95, 0.97, 1.0)
			if b_lbl:
				b_lbl.text = "Dificultad: %s" % translated
				b_lbl.add_theme_color_override("font_color", Color(0.2, 0.3, 0.4, 1.0))
	
	badge.add_theme_stylebox_override("panel", style)


# ── Modos de Juego y Pantalla de Instrucciones ──────────────────────────────

func _on_arcade_selected() -> void:
	var act := _find_activity_in_session(_selected_session, ["flappy", "flexion", "arcade", "pajaro", "bird"])
	if act.is_empty():
		act = _find_active_activity(["flappy", "flexion", "arcade", "pajaro", "bird"])
	if not act.is_empty():
		_current_difficulty_name = act.get("difficulty", "medio")
		_current_difficulty_factor = float(act.get("difficulty_factor", 1.0))
		_session_activity_id = str(act.get("sessionActivityId", act.get("id", "")))
	else:
		_current_difficulty_name = str(_selected_session.get("difficulty", "medio")).to_lower()
		_current_difficulty_factor = _get_diff_factor(_current_difficulty_name)
		_session_activity_id = ""
	
	_selected_game_scene = "res://games/flappy/space_game.tscn"
	_is_functional_selected = false
	_current_exercise_type = "flexion"
	session_duration = 30.0
	_instruction_text = "Hacé flexiones de mano para hacer saltar al pájaro y esquivar los obstáculos."
	_show_instructions_screen()


func _on_functional_selected() -> void:
	var act := _find_activity_in_session(_selected_session, ["botella", "flexion_constante", "vaso", "bottle"])
	if act.is_empty():
		act = _find_active_activity(["botella", "flexion_constante", "vaso", "bottle"])
	if not act.is_empty():
		_current_difficulty_name = act.get("difficulty", "medio")
		_current_difficulty_factor = float(act.get("difficulty_factor", 1.0))
		_session_activity_id = str(act.get("sessionActivityId", act.get("id", "")))
	else:
		_current_difficulty_name = str(_selected_session.get("difficulty", "medio")).to_lower()
		_current_difficulty_factor = _get_diff_factor(_current_difficulty_name)
		_session_activity_id = ""
	
	_selected_game_scene = "res://games/functional/glass_game.tscn"
	_is_functional_selected = true
	_current_exercise_type = "flexion_constante"
	session_duration = 30.0
	_instruction_text = "Mantené la mano flexionada constantemente para empujar la botella hacia el objetivo."
	_show_instructions_screen()


func _on_pinch_selected() -> void:
	var act := _find_activity_in_session(_selected_session, ["pinza", "piano", "pinch"])
	if act.is_empty():
		act = _find_active_activity(["pinza", "piano", "pinch"])
	if not act.is_empty():
		_current_difficulty_name = act.get("difficulty", "medio")
		_current_difficulty_factor = float(act.get("difficulty_factor", 1.0))
		_session_activity_id = str(act.get("sessionActivityId", act.get("id", "")))
	else:
		_current_difficulty_name = str(_selected_session.get("difficulty", "medio")).to_lower()
		_current_difficulty_factor = _get_diff_factor(_current_difficulty_name)
		_session_activity_id = ""
	
	_selected_game_scene = "res://games/pinch/pinch_game.tscn"
	_is_functional_selected = false
	_current_exercise_type = "pinza"
	session_duration = 83.0
	_instruction_text = "Juntá la yema del pulgar con la de cualquier otro dedo al ritmo de las teclas."
	_show_instructions_screen()


func _on_basket_selected() -> void:
	var act := _find_activity_in_session(_selected_session, ["basket", "coordinacion", "coordinacion_3d", "aro", "pelota"])
	if act.is_empty():
		act = _find_active_activity(["basket", "coordinacion", "coordinacion_3d", "aro", "pelota"])
	if not act.is_empty():
		_current_difficulty_name = act.get("difficulty", "medio")
		_current_difficulty_factor = float(act.get("difficulty_factor", 1.0))
		_session_activity_id = str(act.get("sessionActivityId", act.get("id", "")))
	else:
		_current_difficulty_name = str(_selected_session.get("difficulty", "medio")).to_lower()
		_current_difficulty_factor = _get_diff_factor(_current_difficulty_name)
		_session_activity_id = ""
	
	_selected_game_scene = "res://games/basket/basket_game_3d.tscn"
	_is_functional_selected = true
	_current_exercise_type = "coordinacion_3d"
	session_duration = 30.0
	_instruction_text = "Agarra la pelota (flexión), levanta la mano (giroscopio) y soltala para encestar."
	_show_instructions_screen()


func _show_instructions_screen() -> void:
	_show_menu_screen(MenuScreen.NONE)
	_phase = Phase.INSTRUCTION
	_time_left = session_duration
	
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()
		
	var instr_scene := load("res://games/flappy/flappy_instruction.tscn")
	_instruction_overlay = instr_scene.instantiate()
	if _instruction_overlay.has_method("setup"):
		_instruction_overlay.setup(_instruction_text, _is_functional_selected, _current_exercise_type)
	_instruction_overlay.start_requested.connect(_start_minigame)
	add_child(_instruction_overlay)
	
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	_instruction_label.hide()
	_subtitle_label.hide()
	if has_node("%StartGameButton"):
		%StartGameButton.hide()


# ── Lógica de Ejecución del Juego / Telemetría BLE ──────────────────────────

func _process(delta: float) -> void:
	if _phase != Phase.PLAYING:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_finish_session()
	_update_hud()

	# Muestreo periódico de sensores para el histórico de mediciones
	_sample_timer += delta
	if _sample_timer >= SAMPLE_INTERVAL:
		_sample_timer = 0.0
		_capture_sensor_measurements()

	# Actualizar barra de flexión en tiempo real
	var is_thrusting := false
	if _ble_manager != null:
		var flex_val: float = _ble_manager.last_flex_value
		_flex_bar.value = flex_val
		_flex_label.text = "%d%%" % int(flex_val)

		# Cambiar color de la barra según el umbral
		if flex_val >= _flex_detector.flex_threshold:
			_flex_bar.modulate = Color(0, 0.5, 0.5, 1.0)  # Verde
			is_thrusting = true
		elif flex_val >= _flex_detector.release_threshold:
			_flex_bar.modulate = Color(0.8, 0.6, 0.2, 1.0)  # Amarillo/Naranja
		else:
			_flex_bar.modulate = Color(0.6, 0.6, 0.6, 1.0)  # Gris

	# Pasar valor al minijuego
	if is_instance_valid(_minigame_instance):
		if _minigame_instance.has_method("set_thrust"):
			_minigame_instance.set_thrust(is_thrusting)
		if _minigame_instance.has_method("set_flex") and _ble_manager != null:
			_minigame_instance.set_flex(_ble_manager.last_flex_value)


func _capture_sensor_measurements() -> void:
	if _ble_manager == null:
		return
	var now_iso := _get_iso_timestamp_utc()
	# Dedo Pulgar
	_measurements.append({
		"capturedAt": now_iso,
		"type": "THUMB_FLEXION",
		"value": roundi(_ble_manager.pulgar)
	})
	# Dedo Índice
	_measurements.append({
		"capturedAt": now_iso,
		"type": "INDEX_FLEXION",
		"value": roundi(_ble_manager.indice)
	})
	# Dedo Medio
	_measurements.append({
		"capturedAt": now_iso,
		"type": "MIDDLE_FLEXION",
		"value": roundi(_ble_manager.medio)
	})
	# Dedo Anular
	_measurements.append({
		"capturedAt": now_iso,
		"type": "RING_FLEXION",
		"value": roundi(_ble_manager.anular)
	})
	# Dedo Meñique
	_measurements.append({
		"capturedAt": now_iso,
		"type": "LITTLE_FLEXION",
		"value": roundi(_ble_manager.menique)
	})
	# Sensor de Presión / Fuerza (FSR)
	if _ble_manager.presion > 0.0 or _ble_manager.last_fsr_value > 0.0:
		var p_val: float = _ble_manager.presion if _ble_manager.presion > 0.0 else _ble_manager.last_fsr_value
		_measurements.append({
			"capturedAt": now_iso,
			"type": "PRESSURE",
			"value": roundi(p_val)
		})


func _get_iso_timestamp_utc() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	var ms := Time.get_ticks_msec() % 1000
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"],
		ms
	]


func _on_tap_zone_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed := false
		if event is InputEventScreenTouch:
			pressed = event.pressed
		elif event is InputEventMouseButton:
			if _glove_connected:
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				pressed = event.pressed
			else:
				return
		
		if not _glove_connected and is_instance_valid(_minigame_instance) and _minigame_instance.has_method("set_thrust"):
			_minigame_instance.set_thrust(pressed)
			
		if pressed:
			_handle_tap()


func _handle_tap() -> void:
	match _phase:
		Phase.READY, Phase.INSTRUCTION, Phase.FINISHED:
			pass
		Phase.PLAYING:
			_pulse_tap()
			if is_instance_valid(_minigame_instance):
				if _minigame_instance.has_method("trigger_action"):
					_minigame_instance.trigger_action()


func _start_minigame() -> void:
	_phase = Phase.PLAYING
	_started_at_iso = _get_iso_timestamp_utc()
	_measurements.clear()
	_sample_timer = 0.0

	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()
	
	if is_instance_valid(_minigame_instance):
		_minigame_instance.queue_free()
	
	if is_instance_valid(_instruction_image):
		_instruction_image.queue_free()
	if is_instance_valid(_mascot):
		_mascot.queue_free()
		
	# Ocultar fondos locales y del shell contenedor para que se vean juegos 3D y fondos propios
	_set_shell_background_visible(false)
	
	var game_scene := load(_selected_game_scene)
	_minigame_instance = game_scene.instantiate()
	_minigame_instance.score_updated.connect(func(s: int): 
		_taps = s
		_update_hud()
	)
	
	# Configurar el fondo transparente para que se vea el juego
	_tap_zone.color = Color(0, 0, 0, 0)
	_tap_zone.add_child(_minigame_instance)
	if _minigame_instance is Control:
		_minigame_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		_minigame_instance.size = _tap_zone.size
	_tap_zone.move_child(_minigame_instance, 0)
	
	# Inyectar factor de dificultad al detector y al minijuego
	if _flex_detector != null:
		_flex_detector.set_difficulty_factor(_current_difficulty_factor)
	if is_instance_valid(_minigame_instance) and _minigame_instance.has_method("set_difficulty_factor"):
		_minigame_instance.set_difficulty_factor(_current_difficulty_factor)

	if _minigame_instance.has_method("start_game"):
		_minigame_instance.start_game()

	# Notificar al guante por BLE que inició el juego
	if _get_ble_manager() != null:
		var ble = _get_ble_manager()
		ble.send_data("INICIAR_JUEGO\n")
		print("[session_game] Enviado al guante: INICIAR_JUEGO")

	if has_node("%BtnExitGame"):
		get_node("%BtnExitGame").show()


func _set_shell_background_visible(p_visible: bool) -> void:
	if has_node("Background"):
		$Background.visible = p_visible
	if has_node("GlowTop"):
		$GlowTop.visible = p_visible
	var p = get_parent()
	while p != null:
		if p.has_node("Background") and p.get_node("Background") is ColorRect:
			p.get_node("Background").visible = p_visible
		p = p.get_parent()


func _abort_current_game() -> void:
	_phase = Phase.READY
	_time_left = session_duration
	if is_instance_valid(_minigame_instance):
		_minigame_instance.queue_free()
	if _get_ble_manager() != null:
		var ble = _get_ble_manager()
		ble.send_data("FINALIZAR_JUEGO\n")
	_set_shell_background_visible(true)
	_reset_hud()
	if has_node("%BtnExitGame"):
		get_node("%BtnExitGame").hide()
	_show_menu_screen(MenuScreen.GAMES)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _results_panel != null and _results_panel.visible:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
		elif _phase == Phase.PLAYING or _phase == Phase.INSTRUCTION:
			_abort_current_game()
			get_viewport().set_input_as_handled()
		elif _current_menu_screen == MenuScreen.GAMES:
			_on_back_to_sessions()
			get_viewport().set_input_as_handled()
		elif _current_menu_screen == MenuScreen.SESSIONS:
			_on_back_to_treatments()
			get_viewport().set_input_as_handled()
		elif _current_menu_screen == MenuScreen.TREATMENTS:
			_on_back_to_dashboard()
			get_viewport().set_input_as_handled()


func _finish_session() -> void:
	_phase = Phase.FINISHED
	var finished_at_iso := _get_iso_timestamp_utc()

	if has_node("%BtnExitGame"):
		get_node("%BtnExitGame").hide()

	# Notificar al guante por BLE que finalizó el juego
	if _get_ble_manager() != null:
		var ble = _get_ble_manager()
		ble.send_data("FINALIZAR_JUEGO\n")
		print("[session_game] Enviado al guante: FINALIZAR_JUEGO")
	
	# Guardar localmente
	var store = _get_session_store()
	var session: Dictionary = store.save_session(_taps, int(session_duration), _current_exercise_type, _current_difficulty_name, _current_difficulty_factor)
	
	# Enviar mediciones y resultado a la API si hay sesión conectada
	_send_execution_to_api(finished_at_iso)

	_tap_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_results(session)


func _send_execution_to_api(finished_at_iso: String) -> void:
	if _get_api_client() == null:
		return
	var api = _get_api_client()
	if not api.is_authenticated():
		return
	
	var activity_id := _session_activity_id
	if activity_id.is_empty():
		var act := _find_activity_in_session(_selected_session, [_current_exercise_type])
		if act.is_empty():
			act = _find_active_activity([_current_exercise_type])
		activity_id = str(act.get("sessionActivityId", act.get("id", "")))
	
	if activity_id.is_empty():
		print("[session_game] No hay sessionActivityId asociado a esta actividad, omitiendo POST a la API.")
		return
	
	var payload := {
		"sessionActivityId": activity_id,
		"startedAt": _started_at_iso if not _started_at_iso.is_empty() else finished_at_iso,
		"finishedAt": finished_at_iso,
		"gameResult": {
			"score": _taps
		},
		"measurements": _measurements
	}
	
	print("[session_game] Enviando resultados a la API con %d mediciones registradas..." % _measurements.size())
	api.save_session_activity_execution(payload)


func _show_results(session: Dictionary) -> void:
	var taps: int = int(session.get("taps", 0))
	var xp: int = int(session.get("xp_earned", 0))
	var diff_name: String = str(session.get("difficulty", _current_difficulty_name)).capitalize()
	var diff_factor: float = float(session.get("difficulty_factor", _current_difficulty_factor))
	var store = _get_session_store()
	var best: int = store.get_best_taps()
	var is_best := taps >= best and taps > 0
	_results_title.text = "¡Sesión completada!" if taps > 0 else "Sesión finalizada"

	var input_mode := "Flexiones" if _glove_connected else "Toques"
	_results_detail.text = (
		"%s: %d\nDificultad: %s (x%.1f)\nXP ganada: +%d\n%s" % [
			input_mode,
			taps,
			diff_name,
			diff_factor,
			xp,
			"¡Nuevo récord personal!" if is_best else "Seguí practicando para superarte",
		]
	)
	_instruction_label.text = "Tiempo agotado"	
	_subtitle_label.text = "Neuro guardó tu progreso"
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	_results_panel.show()
	var tween := create_tween()
	_results_panel.modulate.a = 0.0
	_results_panel.scale = Vector2(0.92, 0.92)
	tween.set_parallel(true)
	tween.tween_property(_results_panel, "modulate:a", 1.0, 0.35)
	tween.tween_property(_results_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _reset_hud() -> void:
	_phase = Phase.READY
	_time_left = session_duration
	_taps = 0
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_zone.color = Color(0.976, 0.976, 0.965, 1.0)

	if is_instance_valid(_minigame_instance):
		_minigame_instance.queue_free()
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()

	_instruction_label.text = ""
	_instruction_label.hide()
	_subtitle_label.hide()
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	
	if _flex_detector != null:
		_flex_detector.reset()


func _update_hud() -> void:
	_timer_label.text = "%ds" % int(ceil(_time_left))
	_taps_label.text = str(_taps)


func _pulse_tap() -> void:
	_tap_flash.modulate.a = 0.22
	var tween := create_tween()
	tween.tween_property(_tap_flash, "modulate:a", 0.0, 0.18)


var _image_tween: Tween

func _start_image_bob() -> void:
	if _instruction_image == null or not is_inside_tree() or get_tree() == null:
		return
	await get_tree().process_frame
	if _image_tween:
		_image_tween.kill()
	_instruction_image.pivot_offset = _instruction_image.size * 0.5
	_image_tween = create_tween().set_loops()
	_image_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_image_tween.tween_property(_instruction_image, "scale", Vector2(1.04, 1.04), 0.6)
	_image_tween.tween_property(_instruction_image, "scale", Vector2(0.96, 0.96), 0.6)


func _start_mascot_idle() -> void:
	if _mascot == null or not is_inside_tree() or get_tree() == null:
		return
	await get_tree().process_frame
	_mascot.pivot_offset = _mascot.size * 0.5
	var bob := create_tween().set_loops()
	bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_mascot, "scale", Vector2(1.03, 1.03), 1.6)
	bob.tween_property(_mascot, "scale", Vector2(0.97, 0.97), 1.6)


# ── BLE / Guante Háptico ────────────────────────────────────────────────────

func _setup_ble() -> void:
	if _get_ble_manager() != null:
		_ble_manager = _get_ble_manager()
		_glove_connected = _ble_manager.is_connected_to_glove()

		if not _ble_manager.connected.is_connected(_on_glove_connected):
			_ble_manager.connected.connect(_on_glove_connected)
		if not _ble_manager.disconnected.is_connected(_on_glove_disconnected):
			_ble_manager.disconnected.connect(_on_glove_disconnected)
		if not _ble_manager.flex_updated.is_connected(_on_flex_value_updated):
			_ble_manager.flex_updated.connect(_on_flex_value_updated)

	if _flex_detector != null and not _flex_detector.tap_detected.is_connected(_on_flex_tap):
		_flex_detector.tap_detected.connect(_on_flex_tap)

	_update_ble_ui()


func _on_glove_connected(device_name: String) -> void:
	_glove_connected = true
	_update_ble_ui()
	if _phase == Phase.READY:
		_reset_hud()


func _on_glove_disconnected() -> void:
	_glove_connected = false
	_update_ble_ui()
	if _phase == Phase.READY:
		_reset_hud()


func _on_flex_value_updated(_flex_percent: float) -> void:
	pass


func _on_flex_tap() -> void:
	_handle_tap()


func _update_ble_ui() -> void:
	if _ble_status_label == null:
		return

	_flex_panel.visible = false

	if _glove_connected:
		_ble_status_label.text = "🧤 %s" % _ble_manager.connected_device_name
		_ble_status_label.add_theme_color_override(&"font_color", Color(0, 0.36, 0.37))
	else:
		_ble_status_label.text = "🧤 Sin guante"
		_ble_status_label.add_theme_color_override(&"font_color", Color(0.4, 0.5, 0.5))


# ── Botones de Resultados y Salida ──────────────────────────────────────────

func _on_start_button_pressed() -> void:
	pass


func _on_back_pressed() -> void:
	_set_shell_background_visible(true)
	_on_back_to_dashboard()


func _on_retry_pressed() -> void:
	_set_shell_background_visible(true)
	var store = _get_session_store()
	if store:
		store.preselected_exercise = _current_exercise_type
		store.preselected_difficulty = _current_difficulty_name
		store.preselected_difficulty_factor = _current_difficulty_factor
		store.preselected_activity_id = _session_activity_id
	get_tree().change_scene_to_file(GAME_SCENE)
