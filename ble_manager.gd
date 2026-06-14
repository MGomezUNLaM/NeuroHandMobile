extends Node

## Singleton Autoload que maneja la comunicación BLE con el guante háptico.
## En Android usa el plugin nativo GodotBle.
## En PC usa un modo simulación para testing sin hardware.

# ── Señales ──────────────────────────────────────────────────────────────────
signal device_found(device_name: String, address: String)
signal connected(device_name: String)
signal disconnected()
signal flex_updated(flex_percent: float)
signal fsr_updated(fsr_percent: float)
signal scan_started()
signal scan_stopped()
signal error(message: String)

# ── Estado ───────────────────────────────────────────────────────────────────
enum State { IDLE, SCANNING, CONNECTING, CONNECTED }

var state: State = State.IDLE
var connected_device_name: String = ""
var last_flex_value: float = 0.0
var last_fsr_value: float = 0.0

# ── Internos ─────────────────────────────────────────────────────────────────
var _plugin: Object = null  # Referencia al plugin Android (GodotBle)
var _is_android: bool = false
var _sim_enabled: bool = false
var _sim_flex: float = 0.0
var _sim_fsr: float = 0.0
var _sim_timer: float = 0.0

const SIM_UPDATE_RATE := 0.05  # 20Hz como el Arduino real
const SIM_FLEX_SPEED := 300.0  # Velocidad de subida/bajada del flex simulado (%/seg)
const SIM_FLEX_MAX := 80.0     # Valor máximo al "flexionar" simulado


func _ready() -> void:
	_is_android = OS.has_feature("android")
	if _is_android:
		_init_android_plugin()
	else:
		print("[BleManager] No estamos en Android — modo simulación disponible")
		print("[BleManager] En simulación: mantené ESPACIO o click izquierdo para flexionar")


func _process(delta: float) -> void:
	if not _sim_enabled:
		return

	# Detectar input para simulación: ESPACIO o click izquierdo
	var flexing := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if flexing:
		_sim_flex = minf(_sim_flex + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX)
	else:
		_sim_flex = maxf(_sim_flex - SIM_FLEX_SPEED * delta, 0.0)

	# Detectar input para simulación de FSR: F o click derecho
	var pressing_fsr := Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if pressing_fsr:
		_sim_fsr = minf(_sim_fsr + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX)
	else:
		_sim_fsr = maxf(_sim_fsr - SIM_FLEX_SPEED * delta, 0.0)

	_sim_timer += delta
	if _sim_timer >= SIM_UPDATE_RATE:
		_sim_timer = 0.0
		_emit_flex(_sim_flex)
		_emit_fsr(_sim_fsr)


# ── API Pública ──────────────────────────────────────────────────────────────

## Inicia el escaneo de dispositivos BLE.
func start_scan() -> void:
	if _is_android and _plugin != null:
		_plugin.startScan()
	else:
		_start_sim_scan()


## Detiene el escaneo BLE.
func stop_scan() -> void:
	if _is_android and _plugin != null:
		_plugin.stopScan()
	else:
		_stop_sim_scan()


## Conecta a un dispositivo BLE por su dirección MAC.
func connect_device(address: String) -> void:
	if _is_android and _plugin != null:
		state = State.CONNECTING
		_plugin.connectDevice(address)
	else:
		_sim_connect(address)


## Desconecta del dispositivo BLE actual.
func disconnect_device() -> void:
	if _is_android and _plugin != null:
		_plugin.disconnectDevice()
	else:
		_sim_disconnect()


## Devuelve true si hay un dispositivo conectado.
func is_connected_to_glove() -> bool:
	return state == State.CONNECTED


## Solicita permisos BLE en Android.
func request_permissions() -> void:
	if _is_android and _plugin != null:
		_plugin.requestPermissions()


# ── Modo Simulación (PC) ────────────────────────────────────────────────────

## Activa el modo simulación para testing en PC.
func enable_simulation() -> void:
	_sim_enabled = true
	state = State.CONNECTED
	connected_device_name = "Guante Simulado"
	print("[BleManager] Modo simulación activado")
	connected.emit("Guante Simulado")


## Desactiva el modo simulación.
func disable_simulation() -> void:
	_sim_enabled = false
	if not _is_android:
		state = State.IDLE
		connected_device_name = ""
		disconnected.emit()


## Establece el valor de flex en modo simulación (0-100).
func set_sim_flex(value: float) -> void:
	_sim_flex = clampf(value, 0.0, 100.0)


# ── Plugin Android ──────────────────────────────────────────────────────────

func _init_android_plugin() -> void:
	if Engine.has_singleton("GodotBle"):
		_plugin = Engine.get_singleton("GodotBle")
		_connect_plugin_signals()
		print("[BleManager] Plugin GodotBle cargado correctamente")
	else:
		push_warning("[BleManager] Plugin GodotBle no encontrado. ¿Está el APK compilado con Gradle build?")
		error.emit("Plugin BLE no disponible")


func _connect_plugin_signals() -> void:
	if _plugin == null:
		return
	_plugin.connect("ble_device_found", _on_device_found)
	_plugin.connect("ble_connected", _on_connected)
	_plugin.connect("ble_disconnected", _on_disconnected)
	_plugin.connect("ble_flex_updated", _on_flex_updated)
	_plugin.connect("ble_fsr_updated", _on_fsr_updated)
	_plugin.connect("ble_error", _on_error)
	_plugin.connect("ble_scan_started", _on_scan_started)
	_plugin.connect("ble_scan_stopped", _on_scan_stopped)


# ── Callbacks del Plugin ─────────────────────────────────────────────────────

func _on_device_found(name: String, address: String) -> void:
	print("[BLE] Dispositivo encontrado: %s (%s)" % [name, address])
	device_found.emit(name, address)


func _on_connected(name: String) -> void:
	state = State.CONNECTED
	connected_device_name = name
	print("[BLE] Conectado a: %s" % name)
	connected.emit(name)


func _on_disconnected() -> void:
	state = State.IDLE
	connected_device_name = ""
	last_flex_value = 0.0
	print("[BLE] Desconectado")
	disconnected.emit()


func _on_flex_updated(flex_percent: int) -> void:
	_emit_flex(float(flex_percent))


func _on_fsr_updated(fsr_percent: int) -> void:
	_emit_fsr(float(fsr_percent))


func _on_error(msg: String) -> void:
	push_warning("[BLE] Error: %s" % msg)
	error.emit(msg)


func _on_scan_started() -> void:
	state = State.SCANNING
	print("[BLE] Escaneo iniciado")
	scan_started.emit()


func _on_scan_stopped() -> void:
	if state == State.SCANNING:
		state = State.IDLE
	print("[BLE] Escaneo detenido")
	scan_stopped.emit()


# ── Utilidades ───────────────────────────────────────────────────────────────

func _emit_flex(value: float) -> void:
	last_flex_value = value
	flex_updated.emit(value)


func _emit_fsr(value: float) -> void:
	last_fsr_value = value
	fsr_updated.emit(value)


# ── Simulación interna ──────────────────────────────────────────────────────

func _start_sim_scan() -> void:
	state = State.SCANNING
	scan_started.emit()
	print("[SIM] Escaneando dispositivos simulados...")
	# Simula encontrar un dispositivo después de 1 segundo
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			device_found.emit("NeuroHand-Glove", "AA:BB:CC:DD:EE:FF")
	)
	# Auto-detener scan después de 5 segundos
	get_tree().create_timer(5.0).timeout.connect(
		func() -> void:
			if state == State.SCANNING:
				_stop_sim_scan()
	)


func _stop_sim_scan() -> void:
	if state == State.SCANNING:
		state = State.IDLE
	scan_stopped.emit()
	print("[SIM] Escaneo detenido")


func _sim_connect(address: String) -> void:
	state = State.CONNECTING
	print("[SIM] Conectando a %s..." % address)
	# Simula un delay de conexión
	get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			state = State.CONNECTED
			connected_device_name = "NeuroHand-Glove"
			_sim_enabled = true
			connected.emit("NeuroHand-Glove")
			print("[SIM] Conectado exitosamente")
	)


func _sim_disconnect() -> void:
	_sim_enabled = false
	state = State.IDLE
	connected_device_name = ""
	last_flex_value = 0.0
	last_fsr_value = 0.0
	_sim_flex = 0.0
	_sim_fsr = 0.0
	disconnected.emit()
	print("[SIM] Desconectado")
