extends Control

## Shell principal de navegación de KINESIS.
## Administra la barra de navegación inferior (Bottom Navigation Bar) de 4 pestañas:
## - Inicio (tab_home)
## - Tratamiento (tab_missions / ruta de sesiones)
## - Progreso (tab_history / métricas y logros)
## - Perfil (tab_profile / paciente y terapeuta)
## Además gestiona sub-pantallas modales (Conexión BLE, Calibración) y el botón atrás (Android / ESC).

enum View {
	HOME = 0,
	CHALLENGES = 1,
	ACHIEVEMENTS = 2,
	GLOVE = 3,
	CALIBRATION = 4,
	PROFILE = 5
}

const VIEW_SCENES: Dictionary = {
	View.HOME: "res://tab_home.tscn",
	View.CHALLENGES: "res://session_game.tscn",
	View.ACHIEVEMENTS: "res://tab_history.tscn",
	View.GLOVE: "res://ble_connect.tscn",
	View.CALIBRATION: "res://calibration.tscn",
	View.PROFILE: "res://tab_profile.tscn"
}

const COLOR_ACTIVE := Color(0.118, 0.596, 0.647, 1.0) # Teal Kinesis
const COLOR_INACTIVE := Color(0.55, 0.62, 0.68, 1.0) # Slate Gray

var _current_view: int = -1
var _view_cache: Dictionary = {}

@onready var _content: Control = %ContentContainer
@onready var _nav_panel: PanelContainer = %NavPanel

# Botones de navegación
@onready var _btn_tab_home: Button = %BtnTabHome
@onready var _btn_tab_glove: Button = %BtnTabGlove
@onready var _btn_tab_history: Button = %BtnTabHistory
@onready var _btn_tab_profile: Button = %BtnTabProfile

# Iconos y etiquetas de pestañas
@onready var _icon_home: TextureRect = %IconHome
@onready var _label_home: Label = %LabelHome
@onready var _icon_glove: TextureRect = %IconGlove
@onready var _label_glove: Label = %LabelGlove
@onready var _icon_history: TextureRect = %IconHistory
@onready var _label_history: Label = %LabelHistory
@onready var _icon_profile: TextureRect = %IconProfile
@onready var _label_profile: Label = %LabelProfile


func _ready() -> void:
	_btn_tab_home.pressed.connect(func(): switch_to_view(View.HOME))
	_btn_tab_glove.pressed.connect(func(): switch_to_view(View.GLOVE))
	_btn_tab_history.pressed.connect(func(): switch_to_view(View.ACHIEVEMENTS))
	_btn_tab_profile.pressed.connect(func(): switch_to_view(View.PROFILE))

	get_tree().root.size_changed.connect(_apply_safe_area)
	_apply_safe_area()

	switch_to_view(View.HOME)


func _apply_safe_area() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if screen_size.y > 0 and safe_area.size.y > 0 and safe_area.size.y < screen_size.y:
		var window_size := Vector2(get_viewport_rect().size)
		var scale_y := window_size.y / float(screen_size.y)
		var bottom_inset := (screen_size.y - (safe_area.position.y + safe_area.size.y)) * scale_y
		var top_inset := safe_area.position.y * scale_y
		
		# Ajustar márgenes para que la muesca de cámara y la barra de gestos no tapen nada
		if _nav_panel != null:
			_nav_panel.offset_bottom = -max(0.0, bottom_inset)
		if _content != null and _nav_panel != null and _nav_panel.visible:
			_content.offset_bottom = - (72.0 + max(0.0, bottom_inset))
			_content.offset_top = max(0.0, top_inset)
	else:
		if _nav_panel != null:
			_nav_panel.offset_bottom = 0.0
		if _content != null and _nav_panel != null and _nav_panel.visible:
			_content.offset_bottom = -72.0
			_content.offset_top = 0.0


func switch_to_view(view_index: int) -> void:
	if not is_inside_tree() or get_tree() == null:
		return

	if view_index == _current_view:
		return
	if not VIEW_SCENES.has(view_index):
		push_warning("[MainShell] Vista desconocida: %d" % view_index)
		return

	var prev_view: Control = null
	if _current_view >= 0 and _view_cache.has(_current_view) and _view_cache[_current_view] != null:
		prev_view = _view_cache[_current_view]

	# Cargar o mostrar la nueva vista
	var next_view: Control = null
	if not _view_cache.has(view_index) or _view_cache[view_index] == null:
		var scene_path: String = VIEW_SCENES[view_index]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("[MainShell] No se pudo cargar: %s" % scene_path)
			return
		var instance := packed.instantiate()
		instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.add_child(instance)
		_view_cache[view_index] = instance

		# Conectar señales de navegación
		if instance.has_signal("navigate_to"):
			instance.connect("navigate_to", Callable(self, "switch_to_view"))
		elif instance.has_signal("request_tab_change"):
			instance.connect("request_tab_change", Callable(self, "switch_to_view"))
		next_view = instance
	else:
		next_view = _view_cache[view_index]
		next_view.show()
		if next_view.has_method("on_view_activated"):
			next_view.on_view_activated()

	if prev_view != null and prev_view != next_view:
		prev_view.hide()

	if next_view != null:
		next_view.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(next_view, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_current_view = view_index
	_update_nav_bar()


func _update_nav_bar() -> void:
	# En vistas secundarias que tienen su propio flujo (Calibración), ocultar la barra inferior
	if _current_view == View.CALIBRATION:
		_nav_panel.visible = false
		_content.offset_bottom = 0.0
	else:
		_nav_panel.visible = true
		_apply_safe_area()

	# Resaltar pestaña activa
	var active_tab := -1
	match _current_view:
		View.HOME:
			active_tab = 0
		View.GLOVE:
			active_tab = 1
		View.ACHIEVEMENTS:
			active_tab = 2
		View.PROFILE:
			active_tab = 3

	_set_tab_style(_icon_home, _label_home, active_tab == 0)
	_set_tab_style(_icon_glove, _label_glove, active_tab == 1)
	_set_tab_style(_icon_history, _label_history, active_tab == 2)
	_set_tab_style(_icon_profile, _label_profile, active_tab == 3)


func _set_tab_style(icon: TextureRect, label: Label, is_active: bool) -> void:
	var color := COLOR_ACTIVE if is_active else COLOR_INACTIVE
	icon.modulate = color
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 11 if is_active else 10)


## Soporte para botón físico/gesto atrás de Android y Escape de escritorio
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_action()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back_action()
		get_viewport().set_input_as_handled()


func _handle_back_action() -> void:
	match _current_view:
		View.CALIBRATION:
			switch_to_view(View.GLOVE)
		View.GLOVE:
			switch_to_view(View.HOME)
		View.CHALLENGES:
			if _view_cache.has(View.CHALLENGES) and _view_cache[View.CHALLENGES] != null:
				var challenges_inst = _view_cache[View.CHALLENGES]
				if challenges_inst.has_method("handle_back_step"):
					if challenges_inst.handle_back_step():
						return
			switch_to_view(View.HOME)
		View.ACHIEVEMENTS, View.PROFILE:
			switch_to_view(View.HOME)
		View.HOME:
			# Ya está en Home
			pass
