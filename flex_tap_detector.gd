class_name FlexTapDetector
extends Node

## Convierte los valores continuos del flex sensor en eventos discretos de "tap".
## Usa histéresis para evitar falsos positivos: el dedo debe superar el umbral
## de activación Y luego bajar del umbral de liberación antes de contar otro tap.

# ── Señales ──────────────────────────────────────────────────────────────────
signal tap_detected()

# ── Configuración ────────────────────────────────────────────────────────────
## Porcentaje de flexión necesario para detectar un tap (0-100).
@export var flex_threshold: float = 40.0

## Porcentaje al que debe bajar el dedo para "soltar" y permitir otro tap.
## Debe ser menor que flex_threshold para crear histéresis.
@export var release_threshold: float = 30.0

## Porcentaje de presión FSR necesario para detectar un tap (0-100).
@export var fsr_threshold: float = 40.0

## Porcentaje al que debe bajar el FSR para "soltar" y permitir otro tap.
## Debe ser menor que fsr_threshold para crear histéresis.
@export var fsr_release_threshold: float = 30.0

## Tiempo mínimo entre taps en segundos (debounce adicional).
@export var min_tap_interval: float = 0.15

# ── Estado interno ───────────────────────────────────────────────────────────
var _is_flexed: bool = false
var _is_force_pressed: bool = false
var _last_tap_time: float = 0.0
var _current_flex: float = 0.0
var _current_fsr: float = 0.0
var _ble_manager: Node = null


func _ready() -> void:
	# Conectar al BleManager autoload
	if has_node("/root/BleManager"):
		_ble_manager = get_node("/root/BleManager") as BleManager
		_ble_manager.flex_updated.connect(_on_flex_updated)
		_ble_manager.fsr_updated.connect(_on_fsr_updated)
	else:
		push_warning("[FlexTapDetector] BleManager no encontrado como Autoload")


func _on_flex_updated(flex_percent: float) -> void:
	_current_flex = flex_percent
	var current_time := Time.get_ticks_msec() / 1000.0

	if not _is_flexed:
		# Esperando que el dedo supere el umbral
		if flex_percent >= flex_threshold:
			_is_flexed = true
			# Verificar debounce temporal
			if current_time - _last_tap_time >= min_tap_interval:
				_last_tap_time = current_time
				tap_detected.emit()
	else:
		# El dedo ya estaba flexionado, esperando que baje del umbral de release
		if flex_percent <= release_threshold:
			_is_flexed = false


func _on_fsr_updated(fsr_percent: float) -> void:
	_current_fsr = fsr_percent
	var current_time := Time.get_ticks_msec() / 1000.0

	if not _is_force_pressed:
		# Esperando que la fuerza supere el umbral
		if fsr_percent >= fsr_threshold:
			_is_force_pressed = true
			# Verificar debounce temporal
			if current_time - _last_tap_time >= min_tap_interval:
				_last_tap_time = current_time
				tap_detected.emit()
	else:
		# El FSR ya estaba presionado, esperando que baje del umbral de release
		if fsr_percent <= fsr_release_threshold:
			_is_force_pressed = false


## Devuelve el valor actual de flexión (0-100).
func get_current_flex() -> float:
	return _current_flex


## Devuelve el valor actual de presión FSR (0-100).
func get_current_fsr() -> float:
	return _current_fsr


## Devuelve true si el dedo está actualmente flexionado (sobre el umbral).
func is_flexed() -> bool:
	return _is_flexed


## Devuelve true si el FSR está actualmente presionado (sobre el umbral).
func is_force_pressed() -> bool:
	return _is_force_pressed


## Resetea el estado del detector (útil al reiniciar una sesión).
func reset() -> void:
	_is_flexed = false
	_is_force_pressed = false
	_last_tap_time = 0.0
	_current_flex = 0.0
	_current_fsr = 0.0
