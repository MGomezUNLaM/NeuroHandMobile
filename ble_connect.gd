extends Control

## Pantalla de estado y conexión del guante (Mockup 5).

signal navigate_to(view_index: int)

var _ble_manager: Node = null
var _device_buttons: Dictionary = {}
var is_calibrated: bool = true

@onready var status_badge: PanelContainer = %StatusBadge
@onready var dot_color: ColorRect = %DotColor
@onready var status_text: Label = %StatusText
@onready var battery_label: Label = %BatteryLabel
@onready var calib_label: Label = %CalibLabel
@onready var check_icon: TextureRect = %CheckIcon
@onready var btn_calibrar_nuevamente: Button = %BtnCalibrarNuevamente
@onready var scan_button: Button = %ScanButton
@onready var sim_button: Button = %SimButton
@onready var device_list: VBoxContainer = %DeviceList
@onready var connection_controls: VBoxContainer = %ConnectionControls
@onready var btn_back: Button = %BtnBack
@onready var glove_image: TextureRect = %GloveImage if has_node("%GloveImage") else null
@onready var hand_schematic = %HandVisualizer if has_node("%HandVisualizer") else (%HandSchematic if has_node("%HandSchematic") else null)
@onready var hand_visualizer = hand_schematic


func _ready() -> void:
	if has_node("/root/BleManager"):
		_ble_manager = get_node("/root/BleManager")
		_ble_manager.device_found.connect(_on_device_found)
		_ble_manager.connected.connect(_on_connected)
		_ble_manager.disconnected.connect(_on_disconnected)
		_ble_manager.scan_started.connect(_on_scan_started)
		_ble_manager.scan_stopped.connect(_on_scan_stopped)
		_ble_manager.error.connect(_on_error)
		_ble_manager.battery_updated.connect(_on_battery_updated)

	if btn_back != null:
		btn_back.pressed.connect(_on_back_pressed)

	btn_calibrar_nuevamente.pressed.connect(_on_calibrar_pressed)
	scan_button.pressed.connect(_on_scan_pressed)
	sim_button.pressed.connect(_on_sim_pressed)

	sim_button.visible = not OS.has_feature("android")
	_update_ui()


func _on_back_pressed() -> void:
	navigate_to.emit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func on_view_activated() -> void:
	_update_ui()


func _on_calibrar_pressed() -> void:
	navigate_to.emit(4)


func _on_scan_pressed() -> void:
	if _ble_manager == null:
		return
	if _ble_manager.state == 1: # SCANNING
		_ble_manager.stop_scan()
	else:
		_clear_devices()
		_ble_manager.start_scan()


func _on_sim_pressed() -> void:
	if _ble_manager != null:
		_ble_manager.enable_simulation()
		_update_ui()


func _on_device_found(device_name: String, address: String) -> void:
	if _device_buttons.has(address):
		return
	var display_name := device_name if device_name.strip_edges() != "" else "Guante BT05"
	var btn := Button.new()
	btn.text = "🧤 %s (%s)" % [display_name, address]
	btn.custom_minimum_size = Vector2(0, 52)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.94, 0.97, 0.98, 1.0)
	style_normal.border_color = Color(0.118, 0.596, 0.647, 0.6)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(14)
	style_normal.content_margin_left = 16.0
	style_normal.content_margin_right = 16.0
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_normal)
	btn.add_theme_color_override("font_color", Color(0.067, 0.157, 0.235, 1.0))
	btn.add_theme_font_size_override("font_size", 16)
	
	btn.pressed.connect(func(): _on_device_selected(address))
	device_list.add_child(btn)
	_device_buttons[address] = btn


func _on_device_selected(address: String) -> void:
	if _ble_manager != null:
		_ble_manager.stop_scan()
		status_text.text = "Conectando..."
		_ble_manager.connect_device(address)


func _on_connected(_name: String) -> void:
	_update_ui()


func _on_disconnected() -> void:
	_update_ui()


func _on_scan_started() -> void:
	scan_button.text = "Detener búsqueda"
	status_text.text = "Buscando guante..."


func _on_scan_stopped() -> void:
	scan_button.text = "Buscar Guante"
	_update_ui()


func _on_error(msg: String) -> void:
	status_text.text = "Error: %s" % msg


func _on_battery_updated(percentage: int) -> void:
	if battery_label != null:
		battery_label.text = "%d%%" % percentage


func _clear_devices() -> void:
	for child in device_list.get_children():
		child.queue_free()
	_device_buttons.clear()


func _update_ui() -> void:
	var connected := false
	if _ble_manager != null:
		connected = _ble_manager.is_connected_to_glove()
	
	if connected:
		if glove_image:
			glove_image.modulate = Color.WHITE
		if hand_schematic:
			hand_schematic.active_finger = ""
			hand_schematic.completed_fingers = ["pulgar", "indice", "medio", "anular", "menique"]
			hand_schematic.is_open = true
			hand_schematic.flex_progress = 0.0
		dot_color.color = Color(0.18, 0.8, 0.25, 1.0)
		status_text.text = "Conectado"
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Color(0.698, 0.922, 0.698, 1.0)
		badge_style.set_corner_radius_all(20)
		badge_style.content_margin_left = 20.0
		badge_style.content_margin_right = 20.0
		badge_style.content_margin_top = 6.0
		badge_style.content_margin_bottom = 6.0
		status_badge.add_theme_stylebox_override("panel", badge_style)
		
		battery_label.text = "%d%%" % (_ble_manager.battery_level if _ble_manager != null else 85)
		calib_label.text = "Calibrado"
		check_icon.visible = true
		connection_controls.visible = false
	else:
		if glove_image:
			glove_image.modulate = Color(0.75, 0.8, 0.85, 0.85)
		if hand_schematic:
			hand_schematic.active_finger = ""
			hand_schematic.completed_fingers = []
			hand_schematic.is_open = true
			hand_schematic.flex_progress = 0.0
		dot_color.color = Color(0.6, 0.6, 0.6, 1.0)
		status_text.text = "Desconectado"
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Color(0.9, 0.9, 0.9, 1.0)
		badge_style.set_corner_radius_all(20)
		badge_style.content_margin_left = 20.0
		badge_style.content_margin_right = 20.0
		badge_style.content_margin_top = 6.0
		badge_style.content_margin_bottom = 6.0
		status_badge.add_theme_stylebox_override("panel", badge_style)
		
		battery_label.text = "--%"
		calib_label.text = "No calibrado"
		check_icon.visible = false
		connection_controls.visible = true
