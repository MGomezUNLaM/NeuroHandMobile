extends Control

## Pestaña de conexión al guante háptico via BLE.

var _ble_manager: Node = null
var _device_buttons: Dictionary = {}  # address -> Button
var is_connected: bool = false
@onready var _scan_button: Button = %ScanButton
@onready var _device_list: VBoxContainer = %DeviceList
@onready var _status_label: Label = %StatusLabel
@onready var _status_icon: TextureRect = %StatusIcon
@onready var _play_button: Button = %PlayButton
@onready var _skip_button: Button = %SkipButton
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _scan_spinner: Label = %ScanSpinner
@onready var _no_devices_label: Label = %NoDevicesLabel
@onready var _sim_button: Button = %SimButton

var _spinner_angle := 0.0


func _ready() -> void:
	if has_node("/root/BleManager"):
		_ble_manager = get_node("/root/BleManager")
		_ble_manager.device_found.connect(_on_device_found)
		_ble_manager.connected.connect(_on_connected)
		_ble_manager.disconnected.connect(_on_disconnected)
		_ble_manager.scan_started.connect(_on_scan_started)
		_ble_manager.scan_stopped.connect(_on_scan_stopped)
		_ble_manager.error.connect(_on_error)

	_scan_button.pressed.connect(_on_scan_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	_sim_button.pressed.connect(_on_sim_pressed)

	# Ocultar botón de simulación en Android
	_sim_button.visible = not OS.has_feature("android")

	_update_ui()

	# Solicitar permisos al entrar
	if _ble_manager != null:
		_ble_manager.request_permissions()


func _process(delta: float) -> void:
	if _ble_manager != null and _ble_manager.state == 1:  # SCANNING
		_spinner_angle += delta * 360.0
		if _spinner_angle >= 360.0:
			_spinner_angle -= 360.0
		# Animar el icono de escaneo rotando entre caracteres
		var dots := int(_spinner_angle / 90.0) % 4
		_scan_spinner.text = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".substr(int(_spinner_angle / 36.0) % 10, 1)


func _on_scan_pressed() -> void:
	if _ble_manager == null:
		return
	if _ble_manager.state == 1:  # SCANNING
		_ble_manager.stop_scan()
	else:
		# Limpiar lista anterior
		_clear_device_list()
		_ble_manager.start_scan()


func _on_device_found(device_name: String, address: String) -> void:
	if _device_buttons.has(address):
		return  # Ya lo tenemos listado

	var btn := Button.new()
	btn.text = "%s\n%s" % [device_name if device_name != "" else "Dispositivo desconocido", address]
	btn.custom_minimum_size = Vector2(0, 80)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Estilo del botón
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.12, 0.25, 0.9)
	style.border_color = Color(0.12, 0.45, 0.42, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	btn.add_theme_stylebox_override(&"normal", style)

	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.06, 0.18, 0.35, 0.95)
	hover_style.border_color = Color(0.15, 0.7, 0.65, 0.7)
	btn.add_theme_stylebox_override(&"hover", hover_style)

	btn.add_theme_color_override(&"font_color", Color(0.9, 0.93, 0.97))
	btn.add_theme_font_size_override(&"font_size", 18)

	btn.pressed.connect(_on_device_selected.bind(address))
	_device_list.add_child(btn)
	_device_buttons[address] = btn
	_no_devices_label.hide()


func _on_device_selected(address: String) -> void:
	if _ble_manager == null:
		return
	_ble_manager.stop_scan()
	_status_label.text = "Conectando..."
	_status_icon.self_modulate = Color(0.9, 0.8, 0.2) # Amarillo (conectando)
	_ble_manager.connect_device(address)


func _on_connected(device_name: String) -> void:
	_update_ui()


func _on_disconnected() -> void:
	_update_ui()


func _on_scan_started() -> void:
	_scan_button.text = "Detener búsqueda"
	_scan_spinner.show()
	_status_label.text = "Buscando guante..."
	_status_icon.self_modulate = Color(0.2, 0.9, 0.9) # Cian (buscando)


func _on_scan_stopped() -> void:
	_scan_button.text = "Buscar guante"
	_scan_spinner.hide()
	if _ble_manager != null and _ble_manager.state != 3:  # not CONNECTED
		if _device_buttons.is_empty():
			_status_label.text = "No se encontraron dispositivos"
			_status_icon.self_modulate = Color(0.9, 0.3, 0.3) # Rojo (no encontrado)
			_no_devices_label.show()
		else:
			_status_label.text = "Seleccioná un dispositivo"
			_status_icon.self_modulate = Color(0.2, 0.9, 0.9) # Cian (seleccionar)


func _on_error(message: String) -> void:
	_status_label.text = "Error: %s" % message
	_status_icon.self_modulate = Color(0.9, 0.3, 0.3) # Rojo (error)


func _on_play_pressed() -> void:
	pass  # La navegación al juego ahora se hace desde Misiones


func _on_skip_pressed() -> void:
	pass  # Ya no se necesita skip


func _on_disconnect_pressed() -> void:
	if _ble_manager != null:
		_ble_manager.disconnect_device()


func _on_sim_pressed() -> void:
	if _ble_manager != null:
		_ble_manager.enable_simulation()
		_update_ui()


func _clear_device_list() -> void:
	for child in _device_list.get_children():
		child.queue_free()
	_device_buttons.clear()
	_no_devices_label.show()


func _update_ui() -> void:
	if _ble_manager == null:
		return

	is_connected = _ble_manager.is_connected_to_glove()

	_play_button.visible = is_connected
	_disconnect_button.visible = is_connected
	_scan_button.visible = not is_connected
	_sim_button.visible = not is_connected and not OS.has_feature("android")

	if is_connected:
		_status_label.text = "Conectado a %s" % _ble_manager.connected_device_name
		_status_icon.self_modulate = Color(0.15, 0.9, 0.4) # Verde (conectado)
		_scan_spinner.hide()
		_no_devices_label.hide()
	else:
		_status_label.text = "Guante no conectado"
		_status_icon.self_modulate = Color(0.4, 0.46, 0.56) # Gris (desconectado)


func _on_back_pressed() -> void:
	pass  # Ya no se necesita, es pestaña
