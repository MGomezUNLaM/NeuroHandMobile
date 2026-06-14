extends Control

@onready var _level_label: Label = %LevelLabel
@onready var _xp_label: Label = %XPLabel
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _sessions_value: Label = %SessionsValue
@onready var _best_value: Label = %BestValue
@onready var _avg_value: Label = %AvgValue


func _ready() -> void:
	_refresh_profile()


func _refresh_profile() -> void:
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	if store == null:
		return

	var data: Dictionary = store.data
	var level: int = data.get("level", 1)
	var xp: int = data.get("xp", 0)
	var xp_needed: int = level * 250

	_level_label.text = "Nivel %d · Especialista" % level
	_xp_label.text = "%d / %d XP" % [xp, xp_needed]
	_xp_bar.max_value = xp_needed
	_xp_bar.value = xp

	_sessions_value.text = str(store.get_total_sessions())
	_best_value.text = str(store.get_best_taps())
	_avg_value.text = str(store.get_average_taps())
