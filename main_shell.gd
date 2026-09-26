extends Control

## Shell principal de KINESIS.
## Orquesta la navegación tipo "Hub & Spoke":
## - Vista 0 (Home / Hub): 3 grandes tarjetas. Botón inferior = Cerrar sesión.
## - Vistas 1 a 4 (Secundarias): Desafíos, Logros, Guante, Calibración. Botón inferior = Home.

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

const ICON_LOGOUT := preload("res://assets/icons/icon_logout.svg")
const ICON_HOME := preload("res://assets/icons/icon_home_nav.svg")

var _current_view: int = -1
var _view_cache: Dictionary = {}

@onready var _content: Control = %ContentContainer
@onready var _btn_nav_action: Button = %BtnNavAction
@onready var _nav_icon: TextureRect = %NavIcon


func _ready() -> void:
	_btn_nav_action.pressed.connect(_on_nav_action_pressed)
	switch_to_view(View.HOME)


func switch_to_view(view_index: int) -> void:
	if not is_inside_tree() or get_tree() == null:
		return

	if view_index == View.CHALLENGES:
		get_tree().change_scene_to_file.call_deferred("res://session_game.tscn")
		return

	if view_index == _current_view:
		return
	if not VIEW_SCENES.has(view_index):
		push_warning("[MainShell] Vista desconocida: %d" % view_index)
		return

	# Ocultar vista actual si existe
	if _current_view >= 0 and _view_cache.has(_current_view) and _view_cache[_current_view] != null:
		_view_cache[_current_view].hide()

	# Cargar o mostrar la nueva vista
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

		# Conectar una sola señal de navegación para evitar dobles llamadas
		if instance.has_signal("navigate_to"):
			instance.connect("navigate_to", Callable(self, "switch_to_view"))
		elif instance.has_signal("request_tab_change"):
			instance.connect("request_tab_change", Callable(self, "switch_to_view"))
	else:
		_view_cache[view_index].show()
		# Si la vista tiene método _on_activated o refresh, invocarlo
		if _view_cache[view_index].has_method("on_view_activated"):
			_view_cache[view_index].on_view_activated()

	_current_view = view_index
	_update_nav_bar()


func _update_nav_bar() -> void:
	if _current_view == View.HOME:
		_nav_icon.texture = ICON_LOGOUT
		_nav_icon.modulate = Color(0.4, 0.45, 0.5, 1.0)
	else:
		_nav_icon.texture = ICON_HOME
		_nav_icon.modulate = Color(0.4, 0.45, 0.5, 1.0)


func _on_nav_action_pressed() -> void:
	if _current_view == View.HOME:
		# Cerrar sesión
		if has_node("/root/ApiClient"):
			get_node("/root/ApiClient").logout()
		if is_inside_tree() and get_tree() != null:
			get_tree().change_scene_to_file.call_deferred("res://login.tscn")
	else:
		# Regresar al Home
		switch_to_view(View.HOME)
