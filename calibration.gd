extends Control

## Flujo interactivo de calibración del guante en 10 pasos (5 dedos x 2 estados: reposo y full cerrado).
## Protocolo BLE:
## 1. Al iniciar envía "C\n".
## 2. En cada paso al presionar Siguiente envía "Enter:VALOR\n".
## 3. Al finalizar envía "Fin\n".

signal navigate_to(view_index: int)

const TEX_HAND_OPEN := preload("res://assets/icons/hand_open_calib.png")
const TEX_HAND_FIST := preload("res://assets/icons/hand_fist_calib.png")

const STEPS := [
	{"finger": "pulgar", "finger_name": "Pulgar", "state": "reposo", "state_name": "Reposo (abierto)", "is_open": true, "desc": "Mantené el pulgar completamente extendido y relajado."},
	{"finger": "pulgar", "finger_name": "Pulgar", "state": "cerrado", "state_name": "Full Cerrado", "is_open": false, "desc": "Flexioná el pulgar al máximo hacia la palma."},
	{"finger": "indice", "finger_name": "Índice", "state": "reposo", "state_name": "Reposo (abierto)", "is_open": true, "desc": "Mantené el índice completamente extendido y relajado."},
	{"finger": "indice", "finger_name": "Índice", "state": "cerrado", "state_name": "Full Cerrado", "is_open": false, "desc": "Flexioná el índice al máximo hacia la palma."},
	{"finger": "medio", "finger_name": "Medio", "state": "reposo", "state_name": "Reposo (abierto)", "is_open": true, "desc": "Mantené el dedo medio completamente extendido y relajado."},
	{"finger": "medio", "finger_name": "Medio", "state": "cerrado", "state_name": "Full Cerrado", "is_open": false, "desc": "Flexioná el dedo medio al máximo hacia la palma."},
	{"finger": "anular", "finger_name": "Anular", "state": "reposo", "state_name": "Reposo (abierto)", "is_open": true, "desc": "Mantené el anular completamente extendido y relajado."},
	{"finger": "anular", "finger_name": "Anular", "state": "cerrado", "state_name": "Full Cerrado", "is_open": false, "desc": "Flexioná el anular al máximo hacia la palma."},
	{"finger": "menique", "finger_name": "Meñique", "state": "reposo", "state_name": "Reposo (abierto)", "is_open": true, "desc": "Mantené el meñique completamente extendido y relajado."},
	{"finger": "menique", "finger_name": "Meñique", "state": "cerrado", "state_name": "Full Cerrado", "is_open": false, "desc": "Flexioná el meñique al máximo hacia la palma."},
]

var _current_step_idx: int = 0
var _is_completed: bool = false
var _calibration_results: Dictionary = {}
var _last_finger_value: float = 0.0

@onready var hand_graphic: TextureRect = %HandGraphic
@onready var step_label: Label = %StepLabel
@onready var instruction_title: Label = %InstructionTitle
@onready var instruction_subtitle: Label = %InstructionSubtitle
@onready var live_value_label: Label = %LiveValueLabel
@onready var live_progress_bar: ProgressBar = %LiveProgressBar
@onready var calib_progress: ProgressBar = %CalibProgress
@onready var btn_next: Button = %BtnNext
@onready var btn_back: Button = %BtnBack


func _ready() -> void:
	if btn_next:
		btn_next.pressed.connect(_on_next_pressed)
	if btn_back:
		btn_back.pressed.connect(_on_back_pressed)
	start_calibration()


func _on_back_pressed() -> void:
	if not _is_completed and has_node("/root/BleManager"):
		get_node("/root/BleManager").send_data("FIN_CALIBRACION\n")
	navigate_to.emit(3)


func on_view_activated() -> void:
	start_calibration()


func start_calibration() -> void:
	_current_step_idx = 0
	_is_completed = false
	_calibration_results.clear()
	
	# 1. Enviar comando 'C' al guante por BLE para entrar en modo calibración
	if has_node("/root/BleManager"):
		var ble = get_node("/root/BleManager")
		ble.send_data("C\n")
		print("[Calibration] Comando 'C' enviado al guante.")
	
	_update_ui_for_step()


func _process(_delta: float) -> void:
	if _is_completed or _current_step_idx >= STEPS.size():
		return
	
	var step = STEPS[_current_step_idx]
	_last_finger_value = _read_finger_value(step.finger)
	
	if live_value_label:
		live_value_label.text = "Lectura del sensor (%s): %d" % [step.finger_name, int(_last_finger_value)]
	if live_progress_bar:
		live_progress_bar.value = _last_finger_value


func _read_finger_value(finger_key: String) -> float:
	if not has_node("/root/BleManager"):
		return 0.0
	var ble = get_node("/root/BleManager")
	match finger_key:
		"pulgar": return ble.pulgar
		"indice": return ble.indice
		"medio": return ble.medio
		"anular": return ble.anular
		"menique": return ble.menique
		_: return 0.0


func _update_ui_for_step() -> void:
	if _current_step_idx >= STEPS.size():
		_finish_calibration()
		return
		
	var step = STEPS[_current_step_idx]
	
	if step_label:
		step_label.text = "Paso %d de %d" % [_current_step_idx + 1, STEPS.size()]
	if calib_progress:
		calib_progress.max_value = STEPS.size()
		calib_progress.value = _current_step_idx
	
	if hand_graphic:
		hand_graphic.texture = TEX_HAND_OPEN if step.is_open else TEX_HAND_FIST
	
	if instruction_title:
		instruction_title.text = "%s: %s" % [step.finger_name, step.state_name]
	if instruction_subtitle:
		instruction_subtitle.text = step.desc
	
	if btn_next:
		btn_next.text = "Siguiente"


func _on_next_pressed() -> void:
	if _is_completed:
		navigate_to.emit(3) # Regresa a Vista Guante
		return
		
	if _current_step_idx >= STEPS.size():
		return
		
	var step = STEPS[_current_step_idx]
	var val_to_send := int(_last_finger_value)
	
	# Guardar resultado localmente
	var key_name := "%s_%s" % [step.finger, step.state]
	_calibration_results[key_name] = val_to_send
	
	# 2. Enviar string "ENTER:VALOR\n" al guante
	var enter_cmd := "ENTER:%d\n" % val_to_send
	if has_node("/root/BleManager"):
		var ble = get_node("/root/BleManager")
		ble.send_data(enter_cmd)
		print("[Calibration] Enviado al guante: ", enter_cmd.strip_edges())
	
	_current_step_idx += 1
	_update_ui_for_step()


func _finish_calibration() -> void:
	_is_completed = true
	
	# Persistir calibración en almacenamiento local y en SessionStore
	_save_calibration_file()
	
	# Enviar "FIN_CALIBRACION\n" al guante tras un breve respiro para que el buffer serie del Arduino
	# procese el último "ENTER:VALOR" sin solapamiento
	if has_node("/root/BleManager"):
		var ble = get_node("/root/BleManager")
		var timer := get_tree().create_timer(0.2)
		timer.timeout.connect(func():
			ble.send_data("FIN_CALIBRACION\n")
			print("[Calibration] Comando 'FIN_CALIBRACION' enviado al guante.")
		)
	
	if step_label:
		step_label.text = "¡Calibración Completa!"
	if calib_progress:
		calib_progress.value = STEPS.size()
	if instruction_title:
		instruction_title.text = "¡Guante Calibrado con Éxito!"
	if instruction_subtitle:
		instruction_subtitle.text = "Se capturaron y transmitieron los valores de reposo y cierre para los 5 dedos."
	if live_value_label:
		live_value_label.text = "Calibración guardada exitosamente"
	if live_progress_bar:
		live_progress_bar.value = 100.0
	if btn_next:
		btn_next.text = "Finalizar y Volver"


func _save_calibration_file() -> void:
	var path := "user://calibration_data.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_calibration_results, "\t"))
	
	var store := get_node_or_null("/root/SessionStore") as PlayerSessionStore
	if store:
		store.data["calibration"] = _calibration_results
		if store.has_method("_persist"):
			store._persist()
