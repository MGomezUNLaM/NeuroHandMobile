extends Control

const SESSION_DURATION := 30.0
const GAME_SCENE := "res://session_game.tscn"
const DASHBOARD_SCENE := "res://main_shell.tscn"

enum Phase { READY, PLAYING, FINISHED }

var _phase := Phase.READY
var _time_left := SESSION_DURATION
var _taps := 0
var _glove_connected := false

@onready var _tap_zone: ColorRect = %TapZone
@onready var _timer_label: Label = %TimerLabel
@onready var _taps_label: Label = %TapsLabel
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
	_results_panel.hide()
	_tap_zone.gui_input.connect(_on_tap_zone_input)

	# Inicializar BLE
	_setup_ble()

	_reset_hud()
	_start_mascot_idle()


func _process(delta: float) -> void:
	if _phase != Phase.PLAYING:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_finish_session()
	_update_hud()

	# Actualizar barra de flexión en tiempo real
	if _ble_manager != null:
		var flex_val: float = _ble_manager.last_flex_value
		_flex_bar.value = flex_val
		_flex_label.text = "%d%%" % int(flex_val)

		# Cambiar color de la barra según el umbral
		if flex_val >= _flex_detector.flex_threshold:
			_flex_bar.modulate = Color(0.2, 1.0, 0.8, 1.0)  # Verde brillante
		elif flex_val >= _flex_detector.release_threshold:
			_flex_bar.modulate = Color(1.0, 0.85, 0.3, 1.0)  # Amarillo
		else:
			_flex_bar.modulate = Color(0.5, 0.6, 0.7, 1.0)  # Gris


func _on_tap_zone_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		# Si el guante está conectado, ignorar clicks del mouse
		# (en simulación el click se usa para simular flexión)
		if _glove_connected:
			return
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	_handle_tap()



func _handle_tap() -> void:
	match _phase:
		Phase.READY:
			_phase = Phase.PLAYING
			_instruction_image.hide()
			if _glove_connected:
				_instruction_label.text = "¡Dale! Flexioná el dedo"
				_subtitle_label.text = "Cada flexión mayor al %d%% suma puntos" % int(_flex_detector.flex_threshold)
			else:
				_instruction_label.text = "¡Dale! Tocá lo más rápido que puedas"
				_subtitle_label.text = "Cada toque suma puntos"
		Phase.PLAYING:
			_taps += 1
			_pulse_tap()
			_update_hud()
		Phase.FINISHED:
			pass


func _finish_session() -> void:
	_phase = Phase.FINISHED
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	var session: Dictionary = store.save_session(_taps, int(SESSION_DURATION))
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
	_time_left = SESSION_DURATION
	_taps = 0
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_STOP

	_instruction_label.text = ""
	_instruction_image.show()
	_start_image_bob()

	if _glove_connected:
		_subtitle_label.text = "Tocá la pantalla o flexioná el dedo para comenzar"
	else:
		_subtitle_label.text = "Simulá la flexión tocando la pantalla para comenzar"
	_update_hud()

	# Resetear detector de flex
	if _flex_detector != null:
		_flex_detector.reset()


func _update_hud() -> void:
	_timer_label.text = "%d" % int(ceil(_time_left))
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

	_flex_panel.visible = _glove_connected

	if _glove_connected:
		_ble_status_label.text = "🧤 %s" % _ble_manager.connected_device_name
		_ble_status_label.add_theme_color_override(&"font_color", Color(0.2, 0.92, 0.84))
	else:
		_ble_status_label.text = "🧤 Sin guante"
		_ble_status_label.add_theme_color_override(&"font_color", Color(0.5, 0.55, 0.65))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(DASHBOARD_SCENE)


func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
