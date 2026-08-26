extends Control

## Shell principal de la app. Contiene la barra de navegación inferior
## y un container donde se cargan las pestañas (escenas hijas).

const TAB_SCENES: Array[String] = [
	"res://tab_home.tscn",
	"res://tab_history.tscn",
	"res://ble_connect.tscn",
]

const TAB_LABELS: Array[String] = ["Inicio", "Progreso", "Guante"]
const TAB_ICONS_PATHS: Array[String] = [
	"res://assets/icons/icon_home.svg",
	"res://assets/icons/icon_history.svg",
	"res://assets/icons/icon_glove.svg",
]

var _current_tab: int = -1
var _tab_cache: Array[Node] = [null, null, null]
var _tab_buttons: Array[Button] = []

@onready var _content: Control = %ContentContainer
@onready var _nav_bar: HBoxContainer = %NavBar
@onready var _nav_panel: PanelContainer = %NavPanel

const COLOR_ACTIVE := Color(0.0, 0.36, 0.37, 1.0) # #005C5E
const COLOR_INACTIVE := Color(0.63, 0.63, 0.63, 1.0) # #A0A0A0

func _ready() -> void:
	_build_nav_buttons()
	switch_to_tab(0)


## Cambia a la pestaña indicada por índice (0-4).
func switch_to_tab(index: int) -> void:
	if index == _current_tab:
		return
	if index < 0 or index >= TAB_SCENES.size():
		return

	# Ocultar pestaña actual
	if _current_tab >= 0 and _tab_cache[_current_tab] != null:
		_tab_cache[_current_tab].hide()

	# Cargar pestaña si no está en cache
	if _tab_cache[index] == null:
		var scene := load(TAB_SCENES[index]) as PackedScene
		if scene == null:
			push_warning("[MainShell] No se pudo cargar: %s" % TAB_SCENES[index])
			return
		var instance := scene.instantiate()
		instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.add_child(instance)
		_tab_cache[index] = instance

		# Conectar señales especiales de las pestañas
		if instance.has_signal("request_tab_change"):
			instance.request_tab_change.connect(switch_to_tab)
	else:
		_tab_cache[index].show()

	_current_tab = index
	_update_nav_visuals()


func _build_nav_buttons() -> void:
	for i in TAB_LABELS.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 110)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Estilo transparente
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override(&"normal", style)
		btn.add_theme_stylebox_override(&"hover", style)
		btn.add_theme_stylebox_override(&"pressed", style)
		btn.add_theme_stylebox_override(&"focus", style)

		# Contenedor para alinear icono y texto verticalmente
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override(&"separation", 6)
		btn.add_child(vbox)

		# Icono vectorial
		var rect := TextureRect.new()
		rect.name = "Icon"
		rect.texture = load(TAB_ICONS_PATHS[i]) as Texture2D
		rect.custom_minimum_size = Vector2(28, 28)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rect.self_modulate = COLOR_INACTIVE
		vbox.add_child(rect)

		# Texto
		var lbl := Label.new()
		lbl.name = "Label"
		lbl.text = TAB_LABELS[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override(&"font_size", 13)
		lbl.add_theme_color_override(&"font_color", COLOR_INACTIVE)
		vbox.add_child(lbl)

		btn.pressed.connect(_on_tab_pressed.bind(i))
		_nav_bar.add_child(btn)
		_tab_buttons.append(btn)


func _on_tab_pressed(index: int) -> void:
	switch_to_tab(index)


func _update_nav_visuals() -> void:
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		var vbox := btn.get_child(0) as VBoxContainer
		if vbox != null:
			var rect := vbox.get_node(^"Icon") as TextureRect
			var lbl := vbox.get_node(^"Label") as Label
			if i == _current_tab:
				if rect != null: rect.self_modulate = COLOR_ACTIVE
				if lbl != null: lbl.add_theme_color_override(&"font_color", COLOR_ACTIVE)
			else:
				if rect != null: rect.self_modulate = COLOR_INACTIVE
				if lbl != null: lbl.add_theme_color_override(&"font_color", COLOR_INACTIVE)
