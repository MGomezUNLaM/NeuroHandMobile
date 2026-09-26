extends Control

## Pantalla de logros y progreso (Mockup 4).

signal navigate_to(view_index: int)
signal request_tab_change(index: int)

@onready var streak_label: Label = %StreakLabel
@onready var time_label: Label = %TimeLabel


func _ready() -> void:
	_update_stats()


func on_view_activated() -> void:
	_update_stats()


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
