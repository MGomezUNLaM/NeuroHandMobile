extends Control

## Pantalla de logros y progreso (Mockup 4).

signal navigate_to(view_index: int)
signal request_tab_change(index: int)

@onready var streak_label: Label = %StreakLabel
@onready var time_label: Label = %TimeLabel
@onready var btn_back: Button = %BtnBack
@onready var bars_hbox: HBoxContainer = %BarsHBox

var _target_heights: Dictionary = {}


func _ready() -> void:
	if btn_back != null:
		btn_back.pressed.connect(_on_back_pressed)
	_init_bar_animations()
	_update_stats()
	_animate_bars()


func _init_bar_animations() -> void:
	if bars_hbox == null:
		return
	for col in bars_hbox.get_children():
		if col is Control and col.has_node("Bar"):
			var bar = col.get_node("Bar") as Control
			_target_heights[bar] = bar.custom_minimum_size.y


func _animate_bars() -> void:
	if _target_heights.is_empty():
		return
	var delay := 0.0
	for bar in _target_heights.keys():
		var target_h: float = _target_heights[bar]
		bar.custom_minimum_size.y = 8.0
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(bar, "custom_minimum_size:y", target_h, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		delay += 0.04


func _on_back_pressed() -> void:
	navigate_to.emit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func on_view_activated() -> void:
	_update_stats()
	_animate_bars()


func _update_stats() -> void:
	if has_node("/root/SessionStore"):
		var store := get_node("/root/SessionStore")
		var streak: int = int(store.data.get("streak_days", 7))
		streak_label.text = "%d días seguidos" % streak
		
		# Calcular tiempo total en minutos
		var total_seconds := 0
		for s in store.data.get("sessions", []):
			total_seconds += int(s.get("duration_sec", 600))
		
		if total_seconds == 0:
			total_seconds = 12900 # 3h 35m default para coincidir con el mockup
		
		var hours := total_seconds / 3600
		var mins := (total_seconds % 3600) / 60
		if hours > 0:
			time_label.text = "%d horas y %d minutos" % [hours, mins]
		else:
			time_label.text = "%d minutos" % mins
	else:
		streak_label.text = "7 días seguidos"
		time_label.text = "3 horas y 35 minutos"
