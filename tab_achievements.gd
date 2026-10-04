extends Control

@onready var _list: VBoxContainer = %AchievementsList

const ACHIEVEMENTS := [
	{"name": "Primera sesión", "desc": "Completá tu primera sesión", "tier": "Bronce", "key": "first_session", "req": 1},
	{"name": "3 días seguidos", "desc": "Mantené 3 días consecutivos", "tier": "Bronce", "key": "streak_3", "req": 3},
	{"name": "10 sesiones", "desc": "Completá 10 sesiones", "tier": "Plata", "key": "sessions_10", "req": 10},
	{"name": "Nivel 10", "desc": "Alcanzá el nivel 10", "tier": "Plata", "key": "level_10", "req": 10},
	{"name": "50 sesiones", "desc": "Completá 50 sesiones", "tier": "Oro", "key": "sessions_50", "req": 50},
	{"name": "Maestro del agarre", "desc": "Obtené 90%+ en agarre de objetos", "tier": "Oro", "key": "master", "req": -1},
]

var _current_filter: String = "Todos"


func _ready() -> void:
	_refresh_achievements()


func _check_achievement(ach: Dictionary, store: PlayerSessionStore) -> Dictionary:
	var total_sessions: int = store.get_total_sessions() if store else 0
	var level: int = store.data.get("level", 1) if store else 1
	var streak: int = store.data.get("streak_days", 0) if store else 0

	match ach.key:
		"first_session":
			return {"done": total_sessions >= 1, "progress": mini(total_sessions, 1), "max": 1}
		"streak_3":
			return {"done": streak >= 3, "progress": mini(streak, 3), "max": 3}
		"sessions_10":
			return {"done": total_sessions >= 10, "progress": mini(total_sessions, 10), "max": 10}
		"level_10":
			return {"done": level >= 10, "progress": mini(level, 10), "max": 10}
		"sessions_50":
			return {"done": total_sessions >= 50, "progress": mini(total_sessions, 50), "max": 50}
		_:
			return {"done": false, "progress": 0, "max": 1}


func _refresh_achievements() -> void:
	for child in _list.get_children():
		child.queue_free()

	var store := get_node_or_null("/root/SessionStore") as PlayerSessionStore

	for ach in ACHIEVEMENTS:
		if _current_filter != "Todos" and ach.tier != _current_filter:
			continue

		var status := _check_achievement(ach, store)
		_list.add_child(_create_achievement_card(ach, status))


func _create_achievement_card(ach: Dictionary, status: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left = 18.0
	style.content_margin_top = 14.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 14.0
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18

	if status.done:
		style.bg_color = Color(1, 1, 1, 1)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.12, 0.70, 0.65, 0.6)
		style.shadow_color = Color(0.12, 0.70, 0.65, 0.12)
		style.shadow_size = 4
	else:
		style.bg_color = Color(0.97, 0.98, 0.99, 1)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.90, 0.92, 0.94, 1)

	card.add_theme_stylebox_override(&"panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	card.add_child(row)

	# Icono (Trophy SVG) en círculo pastel
	var icon_circle := Panel.new()
	icon_circle.custom_minimum_size = Vector2(44, 44)
	var circle_style := StyleBoxFlat.new()
	circle_style.corner_radius_top_left = 22
	circle_style.corner_radius_top_right = 22
	circle_style.corner_radius_bottom_right = 22
	circle_style.corner_radius_bottom_left = 22

	var tier_color := Color(0.80, 0.50, 0.25) # Bronce
	if ach.tier == "Plata":
		tier_color = Color(0.45, 0.60, 0.75)
	elif ach.tier == "Oro":
		tier_color = Color(0.92, 0.68, 0.15)

	circle_style.bg_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.15)
	icon_circle.add_theme_stylebox_override(&"panel", circle_style)
	row.add_child(icon_circle)

	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(24, 24)
	rect.texture = load("res://assets/icons/icon_trophy_white.svg") as Texture2D
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.self_modulate = tier_color
	icon_circle.add_child(rect)


	# Info
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = ach.name
	name_label.add_theme_font_size_override(&"font_size", 16)
	name_label.add_theme_color_override(&"font_color", Color(0.067, 0.157, 0.235, 1))
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = ach.desc
	desc_label.add_theme_font_size_override(&"font_size", 12)
	desc_label.add_theme_color_override(&"font_color", Color(0.45, 0.55, 0.60, 1))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(desc_label)

	# Progreso o Checkmark
	if status.done:
		var check_lbl := Label.new()
		check_lbl.text = "✓"
		check_lbl.add_theme_font_size_override(&"font_size", 20)
		check_lbl.add_theme_color_override(&"font_color", Color(0.12, 0.70, 0.40, 1))
		check_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(check_lbl)
	elif status.max > 0:
		var prog_label := Label.new()
		prog_label.text = "%d / %d" % [status.progress, status.max]
		prog_label.add_theme_font_size_override(&"font_size", 13)
		prog_label.add_theme_color_override(&"font_color", Color(0.50, 0.60, 0.65, 1))
		prog_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(prog_label)

	return card


func _on_filter_pressed(filter: String) -> void:
	_current_filter = filter
	_refresh_achievements()
