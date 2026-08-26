extends Control

var _ble_manager: Node = null
var _device_buttons: Dictionary = {}
var is_connected: bool = false

@onready var _scan_button: Button = %ScanButton
@onready var _device_list: VBoxContainer = %DeviceList
@onready var _status_label: Label = %StatusLabel
@onready var _status_icon: Panel = %StatusIcon
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _scan_spinner: Label = %ScanSpinner
@onready var _no_devices_label: Label = %NoDevicesLabel
@onready var _sim_button: Button = %SimButton
@onready var _battery_label: Label = %BatteryLabel
@onready var _calib_label: Label = %CalibLabel

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

	if _scan_button: _scan_button.pressed.connect(_on_scan_pressed)
	if _disconnect_button: _disconnect_button.pressed.connect(_on_disconnect_pressed)
	if _sim_button: _sim_button.pressed.connect(_on_sim_pressed)

	if _sim_button:
		_sim_button.visible = not OS.has_feature("android")

	_update_ui()

	if _ble_manager != null:
		_ble_manager.request_permissions()

func _process(delta: float) -> void:
	if _ble_manager != null and _ble_manager.state == 1 and _scan_spinner:  # SCANNING
		_spinner_angle += delta * 360.0
		if _spinner_angle >= 360.0:
			_spinner_angle -= 360.0
		_scan_spinner.text = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".substr(int(_spinner_angle / 36.0) % 10, 1)

func _on_scan_pressed() -> void:
	if _ble_manager == null: return
	if _ble_manager.state == 1:
		_ble_manager.stop_scan()
	else:
		_clear_device_list()
		_ble_manager.start_scan()

func _on_device_found(device_name: String, address: String) -> void:
	if _device_buttons.has(address): return
	var btn := Button.new()
	btn.text = "%s\n%s" % [device_name if device_name != "" else "Dispositivo", address]
	btn.custom_minimum_size = Vector2(0, 60)
	btn.pressed.connect(_on_device_selected.bind(address))
	if _device_list:
		_device_list.add_child(btn)
	_device_buttons[address] = btn
	if _no_devices_label: _no_devices_label.hide()

func _on_device_selected(address: String) -> void:
	if _ble_manager == null: return
	_ble_manager.stop_scan()
	if _status_label: _status_label.text = "Conectando..."
	_ble_manager.connect_device(address)

func _on_connected(_device_name: String) -> void:
	_update_ui()

func _on_disconnected() -> void:
	_update_ui()

func _on_scan_started() -> void:
	if _scan_button: _scan_button.text = "Detener búsqueda"
	if _scan_spinner: _scan_spinner.show()
	if _status_label: _status_label.text = "Buscando guante..."

func _on_scan_stopped() -> void:
	if _scan_button: _scan_button.text = "Buscar guante"
	if _scan_spinner: _scan_spinner.hide()
	if _ble_manager != null and _ble_manager.state != 3:
		if _device_buttons.is_empty():
			if _status_label: _status_label.text = "No se encontraron dispositivos"
			if _no_devices_label: _no_devices_label.show()
		else:
			if _status_label: _status_label.text = "Seleccioná un dispositivo"

func _on_error(message: String) -> void:
	if _status_label: _status_label.text = "Error: %s" % message

func _on_disconnect_pressed() -> void:
	if _ble_manager != null:
		_ble_manager.disconnect_device()

func _on_sim_pressed() -> void:
	if _ble_manager != null:
		_ble_manager.enable_simulation()
		_update_ui()

func _clear_device_list() -> void:
	if not _device_list: return
	for child in _device_list.get_children():
		child.queue_free()
	_device_buttons.clear()
	if _no_devices_label: _no_devices_label.show()

func _update_ui() -> void:
	if _ble_manager == null: return
	is_connected = _ble_manager.is_connected_to_glove()
	
	if _disconnect_button: _disconnect_button.visible = is_connected
	if _scan_button: _scan_button.visible = not is_connected
	if _sim_button: _sim_button.visible = not is_connected and not OS.has_feature("android")

	if is_connected:
		if _status_label: _status_label.text = "Conectado a %s" % _ble_manager.connected_device_name
		if _status_icon:
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.12, 0.8, 0.5) # Verde
			sb.corner_radius_top_left = 16
			sb.corner_radius_top_right = 16
			sb.corner_radius_bottom_right = 16
			sb.corner_radius_bottom_left = 16
			_status_icon.add_theme_stylebox_override("panel", sb)
		if _scan_spinner: _scan_spinner.hide()
		if _no_devices_label: _no_devices_label.hide()
		if _battery_label: _battery_label.text = "82%"
		if _calib_label: _calib_label.text = "Calibrado"
	else:
		if _status_label: _status_label.text = "Guante desconectado"
		if _status_icon:
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.6, 0.6, 0.6) # Gris
			sb.corner_radius_top_left = 16
			sb.corner_radius_top_right = 16
			sb.corner_radius_bottom_right = 16
			sb.corner_radius_bottom_left = 16
			_status_icon.add_theme_stylebox_override("panel", sb)
		if _battery_label: _battery_label.text = "--%"
		if _calib_label: _calib_label.text = "No calibrado"
