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


func _ready() -> void:
	if has_node("/root/BleManager"):
		_ble_manager = get_node("/root/BleManager")
		_ble_manager.device_found.connect(_on_device_found)
		_ble_manager.connected.connect(_on_connected)
		_ble_manager.disconnected.connect(_on_disconnected)
		_ble_manager.scan_started.connect(_on_scan_started)
		_ble_manager.scan_stopped.connect(_on_scan_stopped)
		_ble_manager.error.connect(_on_error)

	btn_calibrar_nuevamente.pressed.connect(_on_calibrar_pressed)
	scan_button.pressed.connect(_on_scan_pressed)
	sim_button.pressed.connect(_on_sim_pressed)

	sim_button.visible = not OS.has_feature("android")
	_update_ui()


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
	var btn := Button.new()
	btn.text = "%s (%s)" % [device_name if device_name != "" else "Guante", address]
	btn.custom_minimum_size = Vector2(0, 48)
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


func _clear_devices() -> void:
	for child in device_list.get_children():
		child.queue_free()
	_device_buttons.clear()


func _update_ui() -> void:
	var connected := false
	if _ble_manager != null:
		connected = _ble_manager.is_connected_to_glove()
	
	if connected:
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
		
		battery_label.text = "80%"
		calib_label.text = "Calibrado"
		check_icon.visible = true
		connection_controls.visible = false
	else:
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
