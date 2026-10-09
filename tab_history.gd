extends Control

## Pantalla de Progreso, Insignias y Récords (Kinesis).
## Diseño inspirado en el mockup alegre y visual con iconos vectoriales ricos a todo color.

signal navigate_to(view_index: int)
signal request_tab_change(index: int)

# Header y Navegación
@onready var btn_back: Button = %BtnBack

# Resumen de Sesiones y Práctica
@onready var session_count_label: Label = %SessionCountLabel
@onready var session_progress_bar: ProgressBar = %SessionProgressBar
@onready var completed_activities_val: Label = %CompletedActivitiesVal
@onready var total_time_val: Label = %TotalTimeVal

# Insignias y Filtros
@onready var badges_unlocked_count: Label = %BadgesUnlockedCount
@onready var filter_all_btn: Button = %FilterAllBtn
@onready var filter_unlocked_btn: Button = %FilterUnlockedBtn
@onready var filter_locked_btn: Button = %FilterLockedBtn
@onready var badges_container: VBoxContainer = %BadgesContainer
@onready var badges_empty_label: Label = %BadgesEmptyLabel

# Récords de Minijuegos
@onready var games_container: VBoxContainer = %GamesContainer
@onready var games_empty_card: PanelContainer = %GamesEmptyCard

# Terapeuta y Tratamiento
@onready var therapist_name_label: Label = %TherapistNameLabel
@onready var therapist_objective_label: Label = %TherapistObjectiveLabel
@onready var avatar_label: Label = %AvatarLabel

# Filtro actual de insignias: "ALL", "UNLOCKED", "LOCKED"
var _current_filter: String = "ALL"
var _cached_badges: Array = []


func _ready() -> void:
	if btn_back != null:
		btn_back.pressed.connect(_on_back_pressed)

	_setup_filter_buttons()

	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		api.treatment_fetched.connect(_on_treatment_fetched)
		api.treatments_fetched.connect(_on_treatments_fetched)
		if api.is_authenticated() and api.current_treatment.is_empty():
			api.get_treatment()

	_load_progress_data()


func _setup_filter_buttons() -> void:
	if filter_all_btn != null:
		filter_all_btn.pressed.connect(func(): _set_filter("ALL"))
	if filter_unlocked_btn != null:
		filter_unlocked_btn.pressed.connect(func(): _set_filter("UNLOCKED"))
	if filter_locked_btn != null:
		filter_locked_btn.pressed.connect(func(): _set_filter("LOCKED"))
	_update_filter_button_styles()


func _set_filter(filter_mode: String) -> void:
	_current_filter = filter_mode
	_update_filter_button_styles()
	_render_badges()


func _update_filter_button_styles() -> void:
	_style_filter_button(filter_all_btn, _current_filter == "ALL")
	_style_filter_button(filter_unlocked_btn, _current_filter == "UNLOCKED")
	_style_filter_button(filter_locked_btn, _current_filter == "LOCKED")


func _style_filter_button(btn: Button, is_active: bool) -> void:
	if btn == null:
		return
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(18)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0

	btn.add_theme_font_size_override("font_size", 15)

	if is_active:
		style.bg_color = Color(0.118, 0.596, 0.647, 1.0) # Teal Kinesis
		btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		style.bg_color = Color(0.93, 0.95, 0.97, 1.0)
		btn.add_theme_color_override("font_color", Color(0.40, 0.50, 0.56, 1.0))

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)



func _on_back_pressed() -> void:
	navigate_to.emit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func on_view_activated() -> void:
	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		if api.is_authenticated() and api.current_treatment.is_empty():
			api.get_treatment()
	_load_progress_data()


func _on_treatment_fetched(_treatment: Dictionary) -> void:
	_load_progress_data()


func _on_treatments_fetched(_treatments: Array) -> void:
	_load_progress_data()


func _load_progress_data() -> void:
	var total_sessions: int = 0
	var completed_sessions: int = 0
	var completed_activities: int = 0
	var total_play_time_sec: int = 0

	var badges_array: Array = []
	var game_results_array: Array = []

	var therapist_name := "Terapeuta asignado"
	var treatment_objective := ""

	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		var t: Dictionary = api.current_treatment
		if t.is_empty() and not api.patient_treatments.is_empty():
			t = api.patient_treatments[0]

		# Si el tratamiento actual no tiene progressStatus pero hay varios en la lista, buscar el que tenga
		if (not t.has("progressStatus") or t.get("progressStatus", {}).is_empty()) and not api.patient_treatments.is_empty():
			for pt in api.patient_treatments:
				if pt is Dictionary and pt.has("progressStatus") and not pt.get("progressStatus", {}).is_empty():
					t = pt
					break
		
		# Terapeuta y objetivo
		var therapist: Dictionary = t.get("therapist", {})
		if not therapist.is_empty():
			var fn := str(therapist.get("firstName", "")).strip_edges()
			var ln := str(therapist.get("lastName", "")).strip_edges()
			if fn != "" or ln != "":
				therapist_name = ("%s %s" % [fn, ln]).strip_edges()
		var obj_str: String = str(t.get("objective", "")).strip_edges()
		if obj_str != "":
			treatment_objective = obj_str
		elif str(t.get("name", "")).strip_edges() != "":
			treatment_objective = str(t.get("name", "")).strip_edges()

		# ProgressStatus (soporte tanto para Dictionary como para String JSON parseado o snake_case)
		var p_status: Variant = t.get("progressStatus", t.get("progress_status", t.get("ProgressStatus", {})))
		if p_status is String:
			p_status = JSON.parse_string(p_status)

		if p_status is Dictionary and not p_status.is_empty():
			# 1. Summary
			var summary: Dictionary = p_status.get("summary", {})
			if not summary.is_empty():
				total_sessions = int(summary.get("totalSessions", 0))
				completed_sessions = int(summary.get("completedSessions", 0))
				completed_activities = int(summary.get("completedActivities", 0))
				total_play_time_sec = int(summary.get("totalPlayTimeSeconds", 0))

			# 2. Badges
			if p_status.has("badges") and p_status["badges"] is Array:
				badges_array = p_status["badges"]

			# 3. GameResults
			if p_status.has("gameResults") and p_status["gameResults"] is Array:
				game_results_array = p_status["gameResults"]
		else:
			# Fallback a sesiones y ejecuciones si el backend no mandó progressStatus
			var raw_sessions: Array = t.get("sessions", [])
			total_sessions = raw_sessions.size()
			for s in raw_sessions:
				if s is Dictionary:
					var is_comp: bool = str(s.get("status", "")).to_lower() in ["completed", "completada"]
					if is_comp:
						completed_sessions += 1
					var s_acts: Array = s.get("sessionActivities", [])
					for act_obj in s_acts:
						if act_obj is Dictionary:
							var exec_dict = act_obj.get("execution", null)
							if exec_dict is Dictionary and not exec_dict.is_empty():
								completed_activities += 1

	# ── 1. Actualizar Resumen ─────────────────────────────────────────────────
	session_count_label.text = "%d de %d sesiones" % [completed_sessions, total_sessions]
	if total_sessions > 0:
		var pct := float(completed_sessions) / float(total_sessions) * 100.0
		session_progress_bar.value = clampf(pct, 0.0, 100.0)
	else:
		session_progress_bar.value = 0.0

	completed_activities_val.text = "%d" % completed_activities

	var hours := total_play_time_sec / 3600
	var mins := (total_play_time_sec % 3600) / 60
	if hours > 0:
		total_time_val.text = "%dh %dm" % [hours, mins]
	elif mins > 0:
		total_time_val.text = "%dm" % mins
	elif total_play_time_sec > 0:
		total_time_val.text = "%ds" % total_play_time_sec
	else:
		total_time_val.text = "0m"

	# ── 2. Insignias ──────────────────────────────────────────────────────────
	_cached_badges = badges_array
	var unlocked_count: int = 0
	for b in _cached_badges:
		if b is Dictionary and bool(b.get("unlocked", false)):
			unlocked_count += 1
	
	if badges_unlocked_count != null:
		badges_unlocked_count.text = "%d de %d" % [unlocked_count, _cached_badges.size()]

	_render_badges()

	# ── 3. Récords de Minijuegos ──────────────────────────────────────────────
	_render_game_results(game_results_array)

	# ── 4. Terapeuta ──────────────────────────────────────────────────────────
	if therapist_name_label != null:
		therapist_name_label.text = "%s • Terapeuta" % therapist_name
	if therapist_objective_label != null:
		if treatment_objective != "":
			therapist_objective_label.text = "Objetivo: %s" % treatment_objective
		else:
			therapist_objective_label.text = "Seguimiento y evolución motriz del tratamiento."
	if avatar_label != null:
		var inits := ""
		for word in therapist_name.split(" ", false):
			if word.length() > 0:
				inits += word.substr(0, 1).to_upper()
		avatar_label.text = inits.substr(0, 2) if inits != "" else "TP"


func _render_badges() -> void:
	if badges_container == null:
		return

	# Limpiar hijos previos
	for child in badges_container.get_children():
		child.queue_free()

	var visible_badges: Array = []
	for b in _cached_badges:
		if not (b is Dictionary):
			continue
		var is_unlocked: bool = bool(b.get("unlocked", false))
		match _current_filter:
			"ALL":
				visible_badges.append(b)
			"UNLOCKED":
				if is_unlocked:
					visible_badges.append(b)
			"LOCKED":
				if not is_unlocked:
					visible_badges.append(b)

	if visible_badges.is_empty():
		if badges_empty_label != null:
			badges_empty_label.visible = true
			if _cached_badges.is_empty():
				badges_empty_label.text = "No hay insignias registradas en este tratamiento."
			elif _current_filter == "UNLOCKED":
				badges_empty_label.text = "Aún no tenés insignias desbloqueadas. ¡Completá actividades para conseguirlas!"
			elif _current_filter == "LOCKED":
				badges_empty_label.text = "¡Felicitaciones! Has desbloqueado todas las insignias."
		return

	if badges_empty_label != null:
		badges_empty_label.visible = false

	for badge in visible_badges:
		badges_container.add_child(_create_badge_card(badge))


func _create_badge_card(badge: Dictionary) -> PanelContainer:
	var is_unlocked: bool = bool(badge.get("unlocked", false))
	var icon_name: String = str(badge.get("icon", badge.get("image", "award"))).strip_edges().to_lower()
	var title: String = str(badge.get("title", "Insignia"))
	var desc: String = str(badge.get("description", ""))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(20)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0

	if is_unlocked:
		style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		style.border_color = Color(0.88, 0.92, 0.95, 1.0)
		style.set_border_width_all(1)
		style.shadow_color = Color(0, 0, 0, 0.02)
		style.shadow_size = 4
		style.shadow_offset = Vector2(0, 1)
	else:
		style.bg_color = Color(0.975, 0.985, 0.99, 1.0)
		style.border_color = Color(0.91, 0.93, 0.95, 1.0)
		style.set_border_width_all(1)

	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	card.add_child(hbox)

	# 1. Badge Squircle Bubble (64x64)
	var icon_badge := PanelContainer.new()
	icon_badge.custom_minimum_size = Vector2(64, 64)
	icon_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style := StyleBoxFlat.new()
	icon_style.set_corner_radius_all(18)
	icon_style.bg_color = _get_badge_bubble_bg(icon_name, is_unlocked)
	icon_badge.add_theme_stylebox_override("panel", icon_style)

	var center := CenterContainer.new()
	icon_badge.add_child(center)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _load_badge_texture(icon_name)
	if is_unlocked:
		icon_rect.modulate = Color.WHITE
	else:
		icon_rect.modulate = Color(0.65, 0.70, 0.75, 0.6)
	center.add_child(icon_rect)

	hbox.add_child(icon_badge)

	# 2. Textos (Título + Descripción)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 3)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 19)
	if is_unlocked:
		title_lbl.add_theme_color_override("font_color", Color(0.08, 0.15, 0.22, 1.0))
	else:
		title_lbl.add_theme_color_override("font_color", Color(0.40, 0.48, 0.54, 1.0))
	vbox.add_child(title_lbl)

	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 15)
		desc_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.64, 1.0))
		vbox.add_child(desc_lbl)

	hbox.add_child(vbox)

	# 3. Pill Tag de Estado (✓ Lista vs 🔒)
	var tag_pill := PanelContainer.new()
	tag_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag_style := StyleBoxFlat.new()
	tag_style.set_corner_radius_all(10)
	tag_style.content_margin_top = 6.0
	tag_style.content_margin_bottom = 6.0

	if is_unlocked:
		tag_style.content_margin_left = 12.0
		tag_style.content_margin_right = 12.0
		tag_style.bg_color = Color(0.88, 0.97, 0.92, 1.0) # Verde suave pastel
		tag_pill.add_theme_stylebox_override("panel", tag_style)

		var tag_lbl := Label.new()
		tag_lbl.text = "✓ Lista"
		tag_lbl.add_theme_font_size_override("font_size", 15)
		tag_lbl.add_theme_color_override("font_color", Color(0.08, 0.60, 0.40, 1.0))
		tag_pill.add_child(tag_lbl)
	else:
		tag_style.content_margin_left = 10.0
		tag_style.content_margin_right = 10.0
		tag_style.bg_color = Color(0.93, 0.95, 0.97, 1.0)
		tag_pill.add_theme_stylebox_override("panel", tag_style)

		var tag_lbl := Label.new()
		tag_lbl.text = "🔒"
		tag_lbl.add_theme_font_size_override("font_size", 15)
		tag_pill.add_child(tag_lbl)

	hbox.add_child(tag_pill)

	return card


func _load_badge_texture(icon_name: String) -> Texture2D:
	var clean := icon_name.strip_edges().to_lower()
	var candidates: Array[String] = [
		"res://assets/icons/icon_badge_%s.svg" % clean,
		"res://assets/icons/icon_%s.svg" % clean,
		"res://assets/icons/icon_badge_award.svg",
		"res://assets/icons/icon_medal.svg"
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _get_badge_bubble_bg(icon_name: String, is_unlocked: bool) -> Color:
	if not is_unlocked:
		return Color(0.92, 0.94, 0.96, 1.0)
	match icon_name:
		"flag":
			return Color(0.85, 0.97, 0.90, 1.0) # Pastel Mint
		"gamepad":
			return Color(0.88, 0.93, 0.99, 1.0) # Pastel Indigo/Blue
		"fire", "flame":
			return Color(0.99, 0.94, 0.85, 1.0) # Pastel Warm Yellow/Amber
		"clock":
			return Color(0.90, 0.96, 0.98, 1.0) # Pastel Ice Teal
		"calendar":
			return Color(0.91, 0.94, 0.99, 1.0) # Pastel Sky Blue
		"trophy":
			return Color(0.98, 0.94, 0.88, 1.0) # Pastel Gold/Cream
		"medal":
			return Color(0.94, 0.90, 0.98, 1.0) # Pastel Lavender
		"award":
			return Color(0.88, 0.97, 0.92, 1.0) # Pastel Emerald
		_:
			return Color(0.90, 0.96, 0.98, 1.0)


func _render_game_results(games: Array) -> void:
	if games_container == null:
		return

	# Limpiar hijos previos (manteniendo games_empty_card si está)
	for child in games_container.get_children():
		if child != games_empty_card:
			child.queue_free()

	if games.is_empty():
		if games_empty_card != null:
			games_empty_card.visible = true
		return

	if games_empty_card != null:
		games_empty_card.visible = false

	for game in games:
		if not (game is Dictionary):
			continue
		games_container.add_child(_create_game_card(game))


func _create_game_card(game: Dictionary) -> PanelContainer:
	var game_id: String = str(game.get("gameId", "")).strip_edges().to_lower()
	var game_name: String = str(game.get("gameName", game_id))
	if game_name == "":
		game_name = "Minijuego"
	var best_score: int = int(game.get("bestScore", 0))
	var plays: int = int(game.get("plays", 0))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(20)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	style.bg_color = Color(0.965, 0.98, 0.99, 1.0)
	style.border_color = Color(0.89, 0.93, 0.95, 1.0)
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	card.add_child(hbox)

	# 1. Bubble de Minijuego (64x64)
	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(64, 64)
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b_style := StyleBoxFlat.new()
	b_style.set_corner_radius_all(18)
	b_style.bg_color = _get_game_bubble_bg(game_id, game_name)
	bubble.add_theme_stylebox_override("panel", b_style)

	var center := CenterContainer.new()
	bubble.add_child(center)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = _get_game_texture(game_id, game_name)
	icon_rect.modulate = Color.WHITE
	center.add_child(icon_rect)
	hbox.add_child(bubble)

	# 2. Info
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 3)

	var name_lbl := Label.new()
	name_lbl.text = game_name
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(0.08, 0.15, 0.22, 1.0))
	vbox.add_child(name_lbl)

	var plays_lbl := Label.new()
	plays_lbl.text = "%d partidas completadas" % plays
	plays_lbl.add_theme_font_size_override("font_size", 15)
	plays_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.64, 1.0))
	vbox.add_child(plays_lbl)

	hbox.add_child(vbox)

	# 3. Score y etiqueta RÉCORD
	var score_vbox := VBoxContainer.new()
	score_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var score_val := Label.new()
	score_val.text = "%d pts" % best_score
	score_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_val.add_theme_font_size_override("font_size", 26)
	score_val.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
	score_vbox.add_child(score_val)

	var score_desc := Label.new()
	score_desc.text = "RÉCORD"
	score_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_desc.add_theme_font_size_override("font_size", 12)
	score_desc.add_theme_color_override("font_color", Color(0.50, 0.58, 0.65, 1.0))
	score_vbox.add_child(score_desc)

	hbox.add_child(score_vbox)

	return card


func _get_game_texture(game_id: String, game_name: String) -> Texture2D:
	var clean := (game_id + " " + game_name).to_lower()
	if clean.contains("bottle") or clean.contains("botella"):
		return load("res://assets/icons/icon_game_bottle.svg") as Texture2D
	elif clean.contains("piano"):
		return load("res://assets/icons/icon_game_piano.svg") as Texture2D
	elif clean.contains("flappy") or clean.contains("pajaro") or clean.contains("pájaro"):
		return load("res://assets/icons/icon_game_flappy.svg") as Texture2D
	elif clean.contains("basket") or clean.contains("baloncesto") or clean.contains("lanzamiento"):
		return load("res://assets/icons/icon_game_basket.svg") as Texture2D
	return load("res://assets/icons/icon_badge_gamepad.svg") as Texture2D


func _get_game_bubble_bg(game_id: String, game_name: String) -> Color:
	var clean := (game_id + " " + game_name).to_lower()
	if clean.contains("bottle") or clean.contains("botella"):
		return Color(0.85, 0.97, 0.92, 1.0) # Mint
	elif clean.contains("piano"):
		return Color(0.91, 0.93, 0.98, 1.0) # Lavender/Blue
	elif clean.contains("flappy") or clean.contains("pajaro") or clean.contains("pájaro"):
		return Color(0.99, 0.95, 0.85, 1.0) # Gold
	elif clean.contains("basket") or clean.contains("baloncesto") or clean.contains("lanzamiento"):
		return Color(0.99, 0.92, 0.88, 1.0) # Peach
	return Color(0.90, 0.96, 0.98, 1.0) # Teal
