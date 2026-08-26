extends Node

## Singleton Autoload que maneja la comunicación BLE con el guante háptico.
## En Android usa el plugin nativo GodotBle.
## En PC usa un modo simulación para testing sin hardware.

# ── Señales ──────────────────────────────────────────────────────────────────
signal device_found(device_name: String, address: String)
signal connected(device_name: String)
signal disconnected()
signal data_received(data: Dictionary)
signal flex_updated(flex_percent: float)
signal flex_fingers_updated(fingers: Array[float])
signal fsr_updated(fsr_percent: float)
signal imu_updated(pitch: float, roll: float, yaw: float)
signal scan_started()
signal scan_stopped()
signal error(message: String)

# ── Estado ───────────────────────────────────────────────────────────────────
enum State { IDLE, SCANNING, CONNECTING, CONNECTED }

var state: State = State.IDLE
var connected_device_name: String = ""

# Sensores individuales (0 a 100%)
var pulgar: float = 0.0
var indice: float = 0.0
var medio: float = 0.0
var anular: float = 0.0
var menique: float = 0.0

# IMU (ángulos en grados)
var pitch: float = 0.0
var roll: float = 0.0
var yaw: float = 0.0

# Fuerza / Presión (0 a 100%)
var presion: float = 0.0

# Promedio de cierre calculado
var promedio_cierre: float = 0.0

# Variables heredadas para compatibilidad con minijuegos existentes
var last_flex_value: float = 0.0
var last_fingers_value: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var last_fsr_value: float = 0.0
var last_imu_value: Vector3 = Vector3.ZERO # x=pitch, y=roll, z=yaw

# ── Internos ─────────────────────────────────────────────────────────────────
var _plugin: Object = null  # Referencia al plugin Android (GodotBle)
var _is_android: bool = false
var _sim_enabled: bool = false

# Variables internas de simulación
var _sim_pulgar: float = 0.0
var _sim_indice: float = 0.0
var _sim_medio: float = 0.0
var _sim_anular: float = 0.0
var _sim_menique: float = 0.0
var _sim_presion: float = 0.0
var _sim_pitch: float = 0.0
var _sim_roll: float = 0.0
var _sim_timer: float = 0.0

const SIM_UPDATE_RATE := 0.05  # 20Hz como el Arduino real
const SIM_FLEX_SPEED := 300.0  # Velocidad de subida/bajada del flex simulado (%/seg)
const SIM_PITCH_SPEED := 180.0 # Velocidad de rotación simulada (deg/seg)
const SIM_FLEX_MAX := 80.0     # Valor máximo al "flexionar" simulado

func _ready() -> void:
	_is_android = OS.has_feature("android")
	
	if _is_android:
		_init_android_plugin()
		# Solicitar permisos al arrancar la app en Android
		call_deferred("request_permissions")
	else:
		print("[BleManager] Modo simulación disponible.")
		print("[BleManager] Controles SIM: ESPACIO=Cierre global | A=Índice, S=Medio, D=Anular, F=Meñique | CLICK DER=Presión | FLECHAS=Pitch/Roll")

func _process(delta: float) -> void:
	if not _sim_enabled:
		return

	# Detectar input flex general (cierre de todos los dedos): ESPACIO o click izquierdo
	var global_pressed := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# Simular dedos individuales:
	# A -> Índice, S -> Medio, D -> Anular, F -> Meñique, T -> Pulgar (o con Space suben todos)
	var key_pulgar := Input.is_key_pressed(KEY_T) or global_pressed
	var key_indice := Input.is_key_pressed(KEY_A) or global_pressed
	var key_medio := Input.is_key_pressed(KEY_S) or global_pressed
	var key_anular := Input.is_key_pressed(KEY_D) or global_pressed
	var key_menique := Input.is_key_pressed(KEY_F) or global_pressed

	_sim_pulgar = minf(_sim_pulgar + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX) if key_pulgar else maxf(_sim_pulgar - SIM_FLEX_SPEED * delta, 0.0)
	_sim_indice = minf(_sim_indice + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX) if key_indice else maxf(_sim_indice - SIM_FLEX_SPEED * delta, 0.0)
	_sim_medio = minf(_sim_medio + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX) if key_medio else maxf(_sim_medio - SIM_FLEX_SPEED * delta, 0.0)
	_sim_anular = minf(_sim_anular + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX) if key_anular else maxf(_sim_anular - SIM_FLEX_SPEED * delta, 0.0)
	_sim_menique = minf(_sim_menique + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX) if key_menique else maxf(_sim_menique - SIM_FLEX_SPEED * delta, 0.0)

	# FSR / Presión: Click derecho o si hay contacto simultáneo
	var any_finger_pressed := (key_indice or key_medio or key_anular or key_menique or key_pulgar) and not global_pressed
	var pressing_fsr := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or any_finger_pressed
	if pressing_fsr:
		_sim_presion = minf(_sim_presion + SIM_FLEX_SPEED * delta, SIM_FLEX_MAX)
	else:
		_sim_presion = maxf(_sim_presion - SIM_FLEX_SPEED * delta, 0.0)

	# Simular IMU Pitch (Arriba/Abajo) y Roll (Izquierda/Derecha)
	if Input.is_action_pressed("ui_up"):
		_sim_pitch = minf(_sim_pitch + SIM_PITCH_SPEED * delta, 90.0)
	elif Input.is_action_pressed("ui_down"):
		_sim_pitch = maxf(_sim_pitch - SIM_PITCH_SPEED * delta, -90.0)
	else:
		_sim_pitch = lerpf(_sim_pitch, 0.0, delta * 5.0)

	if Input.is_action_pressed("ui_right"):
		_sim_roll = minf(_sim_roll + SIM_PITCH_SPEED * delta, 90.0)
	elif Input.is_action_pressed("ui_left"):
		_sim_roll = maxf(_sim_roll - SIM_PITCH_SPEED * delta, -90.0)
	else:
		_sim_roll = lerpf(_sim_roll, 0.0, delta * 5.0)

	_sim_timer += delta
	if _sim_timer >= SIM_UPDATE_RATE:
		_sim_timer = 0.0
		var sim_dict := {
			"pulgar": _sim_pulgar,
			"indice": _sim_indice,
			"medio": _sim_medio,
			"anular": _sim_anular,
			"menique": _sim_menique,
			"pitch": _sim_pitch,
			"roll": _sim_roll,
			"yaw": 0.0,
			"presion": _sim_presion
		}
		_process_parsed_data(sim_dict)


# ── Parser Universal de Tramas del Guante ─────────────────────────────────────

## Parsea una línea de texto recibida por BLE (ej: "pulgar:82,indice:5,medio:6,anular:100,menique:41,pitch:62,roll:-77,presion:3")
func parse_glove_message(raw_line: String) -> Dictionary:
	var result: Dictionary = {}
	var line := raw_line.strip_edges()
	if line.is_empty():
		return result

	# Soporte formato JSON si el guante enviara JSON
	if line.begins_with("{") and line.ends_with("}"):
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			result = parsed
			_process_parsed_data(result)
			return result

	# Formato clave-valor separado por comas
	var pairs := line.split(",")
	for pair in pairs:
		var parts := pair.split(":")
		if parts.size() >= 2:
			var key := parts[0].strip_edges().to_lower()
			var val_str := parts[1].strip_edges()
			if val_str.is_valid_float():
				result[key] = val_str.to_float()
			else:
				result[key] = val_str

	_process_parsed_data(result)
	return result


func _process_parsed_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	var has_fingers := false
	var finger_sum := 0.0
	var finger_count := 0

	# 1. Pulgar
	if data.has("pulgar") or data.has("thumb"):
		pulgar = float(data.get("pulgar", data.get("thumb", 0.0)))
		finger_sum += pulgar
		finger_count += 1
		has_fingers = true

	# 2. Índice
	if data.has("indice") or data.has("índice") or data.has("index"):
		indice = float(data.get("indice", data.get("índice", data.get("index", 0.0))))
		finger_sum += indice
		finger_count += 1
		has_fingers = true

	# 3. Medio / Mayor
	if data.has("medio") or data.has("mayor") or data.has("middle"):
		medio = float(data.get("medio", data.get("mayor", data.get("middle", 0.0))))
		finger_sum += medio
		finger_count += 1
		has_fingers = true

	# 4. Anular
	if data.has("anular") or data.has("ring"):
		anular = float(data.get("anular", data.get("ring", 0.0)))
		finger_sum += anular
		finger_count += 1
		has_fingers = true

	# 5. Meñique
	if data.has("menique") or data.has("meñique") or data.has("pinky"):
		menique = float(data.get("menique", data.get("meñique", data.get("pinky", 0.0))))
		finger_sum += menique
		finger_count += 1
		has_fingers = true

	# Flexión y promedio de cierre
	if has_fingers and finger_count > 0:
		promedio_cierre = finger_sum / float(finger_count)
		last_flex_value = promedio_cierre
		last_fingers_value = [pulgar, indice, medio, anular, menique]
		flex_updated.emit(promedio_cierre)
		flex_fingers_updated.emit(last_fingers_value)
	elif data.has("flex"):
		# Compatibilidad con tramas simples "FLEX:XX"
		last_flex_value = float(data["flex"])
		promedio_cierre = last_flex_value
		flex_updated.emit(last_flex_value)

	# Presión / Fuerza / FSR
	if data.has("presion") or data.has("presión") or data.has("fsr") or data.has("pressure") or data.has("fuerza"):
		presion = float(data.get("presion", data.get("presión", data.get("fsr", data.get("pressure", data.get("fuerza", 0.0))))))
		last_fsr_value = presion
		fsr_updated.emit(presion)

	# IMU: Pitch, Roll, Yaw
	var imu_changed := false
	if data.has("pitch"):
		pitch = float(data["pitch"])
		imu_changed = true
	if data.has("roll"):
		roll = float(data["roll"])
		imu_changed = true
	if data.has("yaw"):
		yaw = float(data["yaw"])
		imu_changed = true

	if imu_changed:
		last_imu_value = Vector3(pitch, roll, yaw)
		imu_updated.emit(pitch, roll, yaw)

	data_received.emit(data)


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
	var clamped := clampf(value, 0.0, 100.0)
	_sim_pulgar = clamped
	_sim_indice = clamped
	_sim_medio = clamped
	_sim_anular = clamped
	_sim_menique = clamped


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
	if _plugin.has_signal("ble_data_received"):
		_plugin.connect("ble_data_received", _on_data_received)
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
	last_fsr_value = 0.0
	pulgar = 0.0
	indice = 0.0
	medio = 0.0
	anular = 0.0
	menique = 0.0
	presion = 0.0
	promedio_cierre = 0.0
	print("[BLE] Desconectado")
	disconnected.emit()


func _on_data_received(line: String) -> void:
	parse_glove_message(line)


func _on_flex_updated(flex_percent: int) -> void:
	# Compatibilidad con eventos directos si la trama era FLEX:XX
	if not _sim_enabled:
		last_flex_value = float(flex_percent)
		promedio_cierre = last_flex_value
		flex_updated.emit(last_flex_value)


func _on_fsr_updated(fsr_percent: int) -> void:
	# Compatibilidad con eventos directos si la trama era FSR:XX
	if not _sim_enabled:
		presion = float(fsr_percent)
		last_fsr_value = presion
		fsr_updated.emit(presion)


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


# ── Simulación interna ──────────────────────────────────────────────────────

func _start_sim_scan() -> void:
	state = State.SCANNING
	scan_started.emit()
	print("[SIM] Escaneando dispositivos simulados...")
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			device_found.emit("NeuroHand-Glove", "AA:BB:CC:DD:EE:FF")
	)
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
	pulgar = 0.0
	indice = 0.0
	medio = 0.0
	anular = 0.0
	menique = 0.0
	presion = 0.0
	promedio_cierre = 0.0
	_sim_pulgar = 0.0
	_sim_indice = 0.0
	_sim_medio = 0.0
	_sim_anular = 0.0
	_sim_menique = 0.0
	_sim_presion = 0.0
	disconnected.emit()
	print("[SIM] Desconectado")

