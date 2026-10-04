extends Control

## Flujo interactivo de calibración del guante en 10 pasos (5 dedos x 2 estados: reposo y full cerrado).
## Protocolo BLE:
## 1. Al iniciar envía "C\n".
## 2. En cada paso al presionar Siguiente envía "ENTER:VALOR\n".
## 3. Al finalizar envía "FIN_CALIBRACION\n".

signal navigate_to(view_index: int)

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

@onready var hand_visualizer = %HandVisualizer if has_node("%HandVisualizer") else (%HandSchematic if has_node("%HandSchematic") else null)
@onready var hand_schematic = hand_visualizer
@onready var step_label: Label = %StepLabel
@onready var instruction_title: Label = %InstructionTitle
@onready var instruction_subtitle: Label = %InstructionSubtitle
@onready var action_badge_label: Label = %ActionBadgeLabel
@onready var action_badge_panel: PanelContainer = %ActionBadgePanel
@onready var target_quality_label: Label = %TargetQualityLabel
@onready var live_value_label: Label = %LiveValueLabel
@onready var live_progress_bar: ProgressBar = %LiveProgressBar
@onready var calib_progress: ProgressBar = %CalibProgress
@onready var btn_next: Button = %BtnNext
@onready var btn_back: Button = %BtnBack

# Chips del stepper superior
@onready var chip_pulgar: PanelContainer = %ChipPulgar
@onready var chip_indice: PanelContainer = %ChipIndice
@onready var chip_medio: PanelContainer = %ChipMedio
@onready var chip_anular: PanelContainer = %ChipAnular
@onready var chip_menique: PanelContainer = %ChipMenique

# Estilos dinámicos
var _style_chip_pending: StyleBoxFlat
var _style_chip_active: StyleBoxFlat
var _style_chip_done: StyleBoxFlat
var _style_badge_open: StyleBoxFlat
var _style_badge_closed: StyleBoxFlat


func _get_ble_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("BleManager")


func _get_session_store() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("SessionStore")


func _ready() -> void:
	_init_styles()
	if btn_next:
		btn_next.pressed.connect(_on_next_pressed)
	if btn_back:
		btn_back.pressed.connect(_on_back_pressed)
	start_calibration()


func _init_styles() -> void:
	_style_chip_pending = StyleBoxFlat.new()
	_style_chip_pending.bg_color = Color(0.94, 0.96, 0.97, 1.0)
	_style_chip_pending.border_color = Color(0.85, 0.88, 0.91, 1.0)
	_style_chip_pending.set_border_width_all(1)
	_style_chip_pending.set_corner_radius_all(12)
	_style_chip_pending.content_margin_left = 8
	_style_chip_pending.content_margin_right = 8
	_style_chip_pending.content_margin_top = 4
	_style_chip_pending.content_margin_bottom = 4

	_style_chip_active = StyleBoxFlat.new()
	_style_chip_active.bg_color = Color(0.90, 0.97, 0.98, 1.0)
	_style_chip_active.border_color = Color(0.118, 0.596, 0.647, 1.0)
	_style_chip_active.set_border_width_all(2)
	_style_chip_active.set_corner_radius_all(12)
	_style_chip_active.content_margin_left = 8
	_style_chip_active.content_margin_right = 8
	_style_chip_active.content_margin_top = 4
	_style_chip_active.content_margin_bottom = 4

	_style_chip_done = StyleBoxFlat.new()
	_style_chip_done.bg_color = Color(0.88, 0.96, 0.92, 1.0)
	_style_chip_done.border_color = Color(0.20, 0.72, 0.45, 1.0)
	_style_chip_done.set_border_width_all(1)
	_style_chip_done.set_corner_radius_all(12)
	_style_chip_done.content_margin_left = 8
	_style_chip_done.content_margin_right = 8
	_style_chip_done.content_margin_top = 4
	_style_chip_done.content_margin_bottom = 4

	_style_badge_open = StyleBoxFlat.new()
	_style_badge_open.bg_color = Color(0.88, 0.96, 0.92, 1.0)
	_style_badge_open.border_color = Color(0.20, 0.72, 0.45, 0.6)
	_style_badge_open.set_border_width_all(1)
	_style_badge_open.set_corner_radius_all(14)
	_style_badge_open.content_margin_left = 12
	_style_badge_open.content_margin_right = 12
	_style_badge_open.content_margin_top = 4
	_style_badge_open.content_margin_bottom = 4

	_style_badge_closed = StyleBoxFlat.new()
	_style_badge_closed.bg_color = Color(0.90, 0.94, 0.99, 1.0)
	_style_badge_closed.border_color = Color(0.25, 0.55, 0.88, 0.6)
	_style_badge_closed.set_border_width_all(1)
	_style_badge_closed.set_corner_radius_all(14)
	_style_badge_closed.content_margin_left = 12
	_style_badge_closed.content_margin_right = 12
	_style_badge_closed.content_margin_top = 4
	_style_badge_closed.content_margin_bottom = 4


func _on_back_pressed() -> void:
	var ble := _get_ble_manager()
	if not _is_completed and ble != null:
		ble.send_data("FIN_CALIBRACION\n")
	navigate_to.emit(3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func on_view_activated() -> void:
	start_calibration()


func start_calibration() -> void:
	_current_step_idx = 0
	_is_completed = false
	_calibration_results.clear()
	
	# 1. Enviar comando 'C' al guante por BLE para entrar en modo calibración
	var ble := _get_ble_manager()
	if ble != null:
		ble.send_data("C\n")
		print("[Calibration] Comando 'C' enviado al guante.")
	
	_update_ui_for_step()


func _process(_delta: float) -> void:
	if _is_completed or _current_step_idx >= STEPS.size():
		return
	
	var step = STEPS[_current_step_idx]
	_last_finger_value = _read_finger_value(step.finger)
	
	if hand_schematic:
		hand_schematic.flex_progress = _last_finger_value / 100.0
	
	if live_value_label:
		live_value_label.text = "Lectura del sensor (%s): %d %%" % [step.finger_name, int(_last_finger_value)]
	if live_progress_bar:
		live_progress_bar.value = _last_finger_value
	
	if target_quality_label:
		if step.is_open:
			if _last_finger_value <= 30.0:
				target_quality_label.text = "🟢 Excelente reposo detectado (relajado)"
				target_quality_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
			else:
				target_quality_label.text = "🟡 Relajá más el dedo para calibrar reposo"
				target_quality_label.add_theme_color_override("font_color", Color(0.75, 0.55, 0.1, 1.0))
		else:
			if _last_finger_value >= 60.0:
				target_quality_label.text = "🟢 Excelente flexión detectada hacia la palma"
				target_quality_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
			else:
				target_quality_label.text = "🟡 Flexioná un poco más hacia la palma"
				target_quality_label.add_theme_color_override("font_color", Color(0.75, 0.55, 0.1, 1.0))


func _read_finger_value(finger_key: String) -> float:
	var ble := _get_ble_manager()
	if ble == null:
		return 0.0
	match finger_key:
		"pulgar": return ble.pulgar
		"indice": return ble.indice
		"medio": return ble.medio
		"anular": return ble.anular
		"menique": return ble.menique
		_: return 0.0


func _get_completed_fingers_list() -> Array:
	var done := []
	if _current_step_idx >= 2: done.append("pulgar")
	if _current_step_idx >= 4: done.append("indice")
	if _current_step_idx >= 6: done.append("medio")
	if _current_step_idx >= 8: done.append("anular")
	if _current_step_idx >= 10: done.append("menique")
	return done


func _get_finger_display_name(key: String) -> String:
	match key:
		"pulgar": return "Pulgar"
		"indice": return "Índice"
		"medio": return "Medio"
		"anular": return "Anular"
		"menique": return "Meñique"
		_: return key.capitalize()


func _update_stepper_chips(current_finger: String) -> void:
	var chips_map = {
		"pulgar": chip_pulgar,
		"indice": chip_indice,
		"medio": chip_medio,
		"anular": chip_anular,
		"menique": chip_menique
	}
	var done_list = _get_completed_fingers_list()
	
	for f_key in chips_map.keys():
		var chip = chips_map[f_key]
		if chip == null:
			continue
		var lbl = chip.find_child("Label*", true, false) as Label
		if not lbl:
			continue
			
		if done_list.has(f_key):
			chip.add_theme_stylebox_override("panel", _style_chip_done)
			lbl.text = "✔ " + _get_finger_display_name(f_key)
			lbl.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
		elif f_key == current_finger and not _is_completed:
			chip.add_theme_stylebox_override("panel", _style_chip_active)
			lbl.text = "▶ " + _get_finger_display_name(f_key)
			lbl.add_theme_color_override("font_color", Color(0.118, 0.596, 0.647, 1.0))
		else:
			chip.add_theme_stylebox_override("panel", _style_chip_pending)
			lbl.text = "• " + _get_finger_display_name(f_key)
			lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.65, 1.0))


func _update_ui_for_step() -> void:
	if _current_step_idx >= STEPS.size():
		_finish_calibration()
		return
		
	var step = STEPS[_current_step_idx]
	
	if hand_schematic:
		hand_schematic.active_finger = step.finger
		hand_schematic.is_open = step.is_open
		hand_schematic.completed_fingers = _get_completed_fingers_list()
	
	_update_stepper_chips(step.finger)
	
	if step_label:
		step_label.text = "Paso %d de %d — %s" % [_current_step_idx + 1, STEPS.size(), step.finger_name]
	if calib_progress:
		calib_progress.max_value = STEPS.size()
		calib_progress.value = _current_step_idx
	
	if action_badge_label and action_badge_panel:
		if step.is_open:
			action_badge_panel.add_theme_stylebox_override("panel", _style_badge_open)
			action_badge_label.text = "🖐 GESTO: REPOSO (EXTENDIDO)"
			action_badge_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
		else:
			action_badge_panel.add_theme_stylebox_override("panel", _style_badge_closed)
			action_badge_label.text = "✊ GESTO: FULL CERRADO (HACIA LA PALMA)"
			action_badge_label.add_theme_color_override("font_color", Color(0.1, 0.45, 0.75, 1.0))
	
	if instruction_title:
		instruction_title.text = "%s: %s" % [step.finger_name, step.state_name]
	if instruction_subtitle:
		instruction_subtitle.text = step.desc
	
	if btn_next:
		btn_next.text = "Confirmar y Siguiente"


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
	var ble := _get_ble_manager()
	if ble != null:
		ble.send_data(enter_cmd)
		print("[Calibration] Enviado al guante: ", enter_cmd.strip_edges())
	
	_current_step_idx += 1
	_update_ui_for_step()


func _finish_calibration() -> void:
	_is_completed = true
	
	if hand_schematic:
		hand_schematic.active_finger = ""
		hand_schematic.completed_fingers = ["pulgar", "indice", "medio", "anular", "menique"]
	_update_stepper_chips("")
	
	# Persistir calibración en almacenamiento local y en SessionStore
	_save_calibration_file()
	
	# Enviar "FIN_CALIBRACION\n" al guante tras un breve respiro para que el buffer serie del Arduino
	# procese el último "ENTER:VALOR" sin solapamiento
	var ble_fin := _get_ble_manager()
	if ble_fin != null and is_inside_tree():
		var timer := get_tree().create_timer(0.2)
		timer.timeout.connect(func():
			ble_fin.send_data("FIN_CALIBRACION\n")
			print("[Calibration] Comando 'FIN_CALIBRACION' enviado al guante.")
		)
	
	if step_label:
		step_label.text = "¡Calibración Completa!"
	if calib_progress:
		calib_progress.value = STEPS.size()
	
	if action_badge_label and action_badge_panel:
		action_badge_panel.add_theme_stylebox_override("panel", _style_badge_open)
		action_badge_label.text = "✔ TODOS LOS DEDOS CALIBRADOS"
		action_badge_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
		
	if instruction_title:
		instruction_title.text = "¡Guante Calibrado con Éxito!"
	if instruction_subtitle:
		instruction_subtitle.text = "Se capturaron y transmitieron los valores de reposo y cierre para los 5 dedos."
	if live_value_label:
		live_value_label.text = "Calibración guardada exitosamente"
	if live_progress_bar:
		live_progress_bar.value = 100.0
	if target_quality_label:
		target_quality_label.text = "🟢 Listo para entrenar"
		target_quality_label.add_theme_color_override("font_color", Color(0.09, 0.52, 0.35, 1.0))
	if btn_next:
		btn_next.text = "Finalizar y Volver"


func _save_calibration_file() -> void:
	var path := "user://calibration_data.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_calibration_results, "\t"))
	
	var store = _get_session_store()
	if store != null and store is PlayerSessionStore:
		store.data["calibration"] = _calibration_results
		if store.has_method("_persist"):
			store._persist()
