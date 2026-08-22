extends Control

var session_duration := 30.0
const GAME_SCENE := "res://session_game.tscn"
const DASHBOARD_SCENE := "res://main_shell.tscn"

enum Phase { READY, INSTRUCTION, PLAYING, FINISHED }

var _phase := Phase.READY
var _time_left := 30.0
var _taps := 0
var _glove_connected := false

var _minigame_instance: Node = null
var _selected_game_scene: String = ""
var _instruction_overlay: Node = null
var _current_exercise_type: String = "flexion"

@onready var _tap_zone: ColorRect = %TapZone
@onready var _timer_label: Label = %TimerLabel
@onready var _taps_label: Label = %TapsLabelOld
@onready var _instruction_image: TextureRect = %InstructionImage
@onready var _instruction_label: Label = %InstructionLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _results_panel: PanelContainer = %ResultsPanel
@onready var _results_title: Label = %ResultsTitle
@onready var _results_detail: Label = %ResultsDetail
@onready var _mascot: TextureRect = %MascotBackdrop
@onready var _tap_flash: ColorRect = %TapFlash

# ── Nodos BLE / Flex ─────────────────────────────────────────────────────────
@onready var _flex_detector: FlexTapDetector = %FlexTapDetector
@onready var _flex_bar: ProgressBar = %FlexBar
@onready var _flex_label: Label = %FlexLabel
@onready var _ble_status_label: Label = %BleStatusLabel
@onready var _flex_panel: PanelContainer = %FlexPanel

var _ble_manager: Node = null


func _ready() -> void:
	if has_node("%GameSelectionMenu"):
		%GameSelectionMenu.show()
	_results_panel.hide()
	_tap_zone.gui_input.connect(_on_tap_zone_input)
	
	if has_node("%StartGameButton"):
		%StartGameButton.hide()
		%StartGameButton.pressed.connect(_on_start_button_pressed)

	# Inicializar BLE
	_setup_ble()

	_reset_hud()
	_start_mascot_idle()
	
	var store := get_node_or_null("/root/SessionStore") as PlayerSessionStore
	if store and store.preselected_exercise == "pinza":
		store.preselected_exercise = ""
		_on_pinch_selected()
	elif store and store.preselected_exercise == "coordinacion_3d":
		store.preselected_exercise = ""
		_on_basket_selected()


func _process(delta: float) -> void:
	if _phase != Phase.PLAYING:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_finish_session()
	_update_hud()

	# Actualizar barra de flexión en tiempo real
	var is_thrusting := false
	if _ble_manager != null:
		var flex_val: float = _ble_manager.last_flex_value
		_flex_bar.value = flex_val
		_flex_label.text = "%d%%" % int(flex_val)

		# Cambiar color de la barra según el umbral
		if flex_val >= _flex_detector.flex_threshold:
			_flex_bar.modulate = Color(0, 0.5, 0.5, 1.0)  # Verde
			is_thrusting = true
		elif flex_val >= _flex_detector.release_threshold:
			_flex_bar.modulate = Color(0.8, 0.6, 0.2, 1.0)  # Amarillo/Naranja
		else:
			_flex_bar.modulate = Color(0.6, 0.6, 0.6, 1.0)  # Gris

	# Pasar valor al minijuego
	if is_instance_valid(_minigame_instance):
		if _minigame_instance.has_method("set_thrust"):
			_minigame_instance.set_thrust(is_thrusting)
		if _minigame_instance.has_method("set_flex") and _ble_manager != null:
			_minigame_instance.set_flex(_ble_manager.last_flex_value)


func _on_tap_zone_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed := false
		if event is InputEventScreenTouch:
			pressed = event.pressed
		elif event is InputEventMouseButton:
			# Si el guante está conectado, ignorar clicks del mouse
			if _glove_connected:
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				pressed = event.pressed
			else:
				return
		
		if not _glove_connected and is_instance_valid(_minigame_instance) and _minigame_instance.has_method("set_thrust"):
			_minigame_instance.set_thrust(pressed)
			
		if pressed:
			_handle_tap()



func _handle_tap() -> void:
	match _phase:
		Phase.READY:
			pass
		Phase.INSTRUCTION:
			pass
		Phase.PLAYING:
			_pulse_tap()
			if is_instance_valid(_minigame_instance):
				if _minigame_instance.has_method("trigger_action"):
					_minigame_instance.trigger_action()
		Phase.FINISHED:
			pass

func _show_instruction() -> void:
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()
	var instr_scene := load("res://games/flappy/flappy_instruction.tscn")
	_instruction_overlay = instr_scene.instantiate()
	_instruction_overlay.start_requested.connect(_start_minigame)
	add_child(_instruction_overlay)

func _start_minigame() -> void:
	_phase = Phase.PLAYING
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()
	
	if is_instance_valid(_minigame_instance):
		_minigame_instance.queue_free()
	
	if is_instance_valid(_instruction_image):
		_instruction_image.queue_free()
	if is_instance_valid(_mascot):
		_mascot.queue_free()
		
	# Ocultar fondos para que se vea el 3D
	if has_node("Background"):
		$Background.hide()
	if has_node("GlowTop"):
		$GlowTop.hide()
	
	var game_scene := load(_selected_game_scene)
	_minigame_instance = game_scene.instantiate()
	_minigame_instance.score_updated.connect(func(s: int): 
		_taps = s
		_update_hud()
	)
	
	# Configurar el fondo transparente para que se vea el juego
	_tap_zone.color = Color(0, 0, 0, 0)
	_tap_zone.add_child(_minigame_instance)
	if _minigame_instance is Control:
		_minigame_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		_minigame_instance.size = _tap_zone.size
	_tap_zone.move_child(_minigame_instance, 0)
	
	if _minigame_instance.has_method("start_game"):
		_minigame_instance.start_game()



func _finish_session() -> void:
	_phase = Phase.FINISHED
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	var session: Dictionary = store.save_session(_taps, int(session_duration), _current_exercise_type)
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_results(session)


func _show_results(session: Dictionary) -> void:
	var taps: int = int(session.get("taps", 0))
	var xp: int = int(session.get("xp_earned", 0))
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	var best: int = store.get_best_taps()
	var is_best := taps >= best and taps > 0
	_results_title.text = "¡Sesión completada!" if taps > 0 else "Sesión finalizada"

	var input_mode := "Flexiones" if _glove_connected else "Toques"
	_results_detail.text = (
		"%s: %d\nXP ganada: +%d\n%s" % [
			input_mode,
			taps,
			xp,
			"¡Nuevo récord personal!" if is_best else "Seguí practicando para superarte",
		]
	)
	_instruction_label.text = "Tiempo agotado"	
	_subtitle_label.text = "Neuro guardó tu progreso"
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	_results_panel.show()
	var tween := create_tween()
	_results_panel.modulate.a = 0.0
	_results_panel.scale = Vector2(0.92, 0.92)
	tween.set_parallel(true)
	tween.tween_property(_results_panel, "modulate:a", 1.0, 0.35)
	tween.tween_property(_results_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _reset_hud() -> void:
	_phase = Phase.READY
	_time_left = session_duration
	_taps = 0
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_zone.color = Color(0.976, 0.976, 0.965, 1.0) # Restaurar color claro de fondo

	if is_instance_valid(_minigame_instance):
		_minigame_instance.queue_free()
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()

	_instruction_label.text = ""
	_instruction_label.hide()
	_subtitle_label.hide()
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	
	# Resetear detector de flex
	if _flex_detector != null:
		_flex_detector.reset()


func _update_hud() -> void:
	_timer_label.text = "%ds" % int(ceil(_time_left))
	_taps_label.text = str(_taps)


func _pulse_tap() -> void:
	_tap_flash.modulate.a = 0.22
	var tween := create_tween()
	tween.tween_property(_tap_flash, "modulate:a", 0.0, 0.18)

var _image_tween: Tween

func _start_image_bob() -> void:
	if _instruction_image == null:
		return
	await get_tree().process_frame
	if _image_tween:
		_image_tween.kill()
	_instruction_image.pivot_offset = _instruction_image.size * 0.5
	_image_tween = create_tween().set_loops()
	_image_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_image_tween.tween_property(_instruction_image, "scale", Vector2(1.04, 1.04), 0.6)
	_image_tween.tween_property(_instruction_image, "scale", Vector2(0.96, 0.96), 0.6)


func _start_mascot_idle() -> void:
	if _mascot == null:
		return
	await get_tree().process_frame
	_mascot.pivot_offset = _mascot.size * 0.5
	var bob := create_tween().set_loops()
	bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_mascot, "scale", Vector2(1.03, 1.03), 1.6)
	bob.tween_property(_mascot, "scale", Vector2(0.97, 0.97), 1.6)


# ── BLE / Guante Háptico ────────────────────────────────────────────────────

func _setup_ble() -> void:
	# Obtener referencia al BleManager autoload
	if has_node("/root/BleManager"):
		_ble_manager = get_node("/root/BleManager") as BleManager
		_glove_connected = _ble_manager.is_connected_to_glove()

		# Conectar señales del BleManager
		_ble_manager.connected.connect(_on_glove_connected)
		_ble_manager.disconnected.connect(_on_glove_disconnected)
		_ble_manager.flex_updated.connect(_on_flex_value_updated)

	# Conectar señal del detector de flex
	if _flex_detector != null:
		_flex_detector.tap_detected.connect(_on_flex_tap)

	# Actualizar UI según estado de conexión
	_update_ble_ui()


func _on_glove_connected(device_name: String) -> void:
	_glove_connected = true
	_update_ble_ui()
	if _phase == Phase.READY:
		_reset_hud()


func _on_glove_disconnected() -> void:
	_glove_connected = false
	_update_ble_ui()
	if _phase == Phase.READY:
		_reset_hud()


func _on_flex_value_updated(_flex_percent: float) -> void:
	# La barra se actualiza en _process() para mayor fluidez
	pass


func _on_flex_tap() -> void:
	# Una flexión del dedo cuenta como un tap
	_handle_tap()


func _update_ble_ui() -> void:
	if _ble_status_label == null:
		return

	_flex_panel.visible = false

	if _glove_connected:
		_ble_status_label.text = "🧤 %s" % _ble_manager.connected_device_name
		_ble_status_label.add_theme_color_override(&"font_color", Color(0, 0.36, 0.37))
	else:
		_ble_status_label.text = "🧤 Sin guante"
		_ble_status_label.add_theme_color_override(&"font_color", Color(0.4, 0.5, 0.5))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(DASHBOARD_SCENE)

var _is_functional_selected: bool = false
var _instruction_text: String = ""

func _on_arcade_selected() -> void:
	_selected_game_scene = "res://games/flappy/space_game.tscn"
	_is_functional_selected = false
	_current_exercise_type = "flexion"
	session_duration = 30.0
	_instruction_text = "Hacé flexiones de mano para hacer saltar al pájaro y esquivar los obstáculos."
	_show_instructions_screen()

func _on_functional_selected() -> void:
	_selected_game_scene = "res://games/functional/glass_game.tscn"
	_is_functional_selected = true
	_current_exercise_type = "flexion_constante"
	session_duration = 30.0
	_instruction_text = "Mantené la mano flexionada constantemente para empujar la botella hacia el objetivo."
	_show_instructions_screen()

func _on_pinch_selected() -> void:
	_selected_game_scene = "res://games/pinch/pinch_game.tscn"
	_is_functional_selected = false
	_current_exercise_type = "pinza"
	session_duration = 83.0
	_instruction_text = "Juntá la yema del pulgar con la de cualquier otro dedo al ritmo de las teclas."
	_show_instructions_screen()

func _on_basket_selected() -> void:
	_selected_game_scene = "res://games/basket/basket_game_3d.tscn"
	_is_functional_selected = true
	_current_exercise_type = "coordinacion_3d"
	session_duration = 30.0
	_instruction_text = "Agarra la pelota (flexión), levanta la mano (giroscopio) y soltala para encestar."
	_show_instructions_screen()

func _show_instructions_screen() -> void:
	%GameSelectionMenu.hide()
	_phase = Phase.INSTRUCTION
	_time_left = session_duration # Aplicar la duración real al timer
	
	if is_instance_valid(_instruction_overlay):
		_instruction_overlay.queue_free()
		
	var instr_scene := load("res://games/flappy/flappy_instruction.tscn")
	_instruction_overlay = instr_scene.instantiate()
	if _instruction_overlay.has_method("setup"):
		_instruction_overlay.setup(_instruction_text, _is_functional_selected, _current_exercise_type)
	_instruction_overlay.start_requested.connect(_start_minigame)
	add_child(_instruction_overlay)
	
	if is_instance_valid(_instruction_image):
		_instruction_image.hide()
	_instruction_label.hide()
	_subtitle_label.hide()
	if has_node("%StartGameButton"):
		%StartGameButton.hide()

func _on_start_button_pressed() -> void:
	pass

func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
