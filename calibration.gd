extends Control

## Flujo interactivo de calibración del guante en 2 pasos de 5 segundos:
## Paso 1: Mano abierta (Mockup 2)
## Paso 2: Mano cerrada / puño (Mockup 3)

signal navigate_to(view_index: int)

enum Step { OPEN_HAND, CLOSED_FIST, COMPLETED }

const STEP_DURATION := 5.0
const TEX_HAND_OPEN := preload("res://assets/icons/hand_open_calib.png")
const TEX_HAND_FIST := preload("res://assets/icons/hand_fist_calib.png")

var _current_step: Step = Step.OPEN_HAND
var _step_elapsed: float = 0.0
var _is_running: bool = false

@onready var hand_graphic: TextureRect = %HandGraphic
@onready var instruction_title: Label = %InstructionTitle
@onready var instruction_duration: Label = %InstructionDuration
@onready var calib_progress: ProgressBar = %CalibProgress
@onready var countdown_label: Label = %CountdownLabel


func _ready() -> void:
	calib_progress.max_value = STEP_DURATION
	start_calibration()


func on_view_activated() -> void:
	start_calibration()


func start_calibration() -> void:
	_current_step = Step.OPEN_HAND
	_step_elapsed = 0.0
	_is_running = true
	_update_step_visuals()


func _process(delta: float) -> void:
	if not _is_running:
		return

	_step_elapsed += delta
	calib_progress.value = clampf(_step_elapsed, 0.0, STEP_DURATION)
	
	var remaining := maxi(1, int(ceil(STEP_DURATION - _step_elapsed)))
	countdown_label.text = "%d..." % remaining

	if _step_elapsed >= STEP_DURATION:
		_on_step_finished()


func _update_step_visuals() -> void:
	_step_elapsed = 0.0
	calib_progress.value = 0.0
	countdown_label.text = "5..."

	if _current_step == Step.OPEN_HAND:
		hand_graphic.texture = TEX_HAND_OPEN
		instruction_title.text = "Mantené la mano completamente abierta"
		instruction_duration.text = "durante 5 segundos"
	elif _current_step == Step.CLOSED_FIST:
		hand_graphic.texture = TEX_HAND_FIST
		instruction_title.text = "Mantené la mano completamente cerrada"
		instruction_duration.text = "durante 5 segundos"


func _on_step_finished() -> void:
	if _current_step == Step.OPEN_HAND:
		# Pasar al paso 2: Mano cerrada
		_current_step = Step.CLOSED_FIST
		_update_step_visuals()
	elif _current_step == Step.CLOSED_FIST:
		# Calibración completada
		_is_running = false
		_current_step = Step.COMPLETED
		instruction_title.text = "¡Guante calibrado con éxito!"
		instruction_duration.text = "Excelente"
		countdown_label.text = "✓"
		
		# Esperar 1 segundo y volver a la pantalla del guante
		get_tree().create_timer(1.2).timeout.connect(func():
			navigate_to.emit(3) # Regresa a Vista Guante
		)
