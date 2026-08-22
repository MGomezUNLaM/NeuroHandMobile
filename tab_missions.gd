extends Control

const GAME_SCENE := "res://session_game.tscn"

@onready var _points_label: Label = %PointsLabel
@onready var _missions_list: VBoxContainer = %MissionsList
@onready var _toast_label: Label = %ToastLabel

var _toast_tween: Tween = null


func _ready() -> void:
	_refresh_points()
	_toast_label.modulate.a = 0.0


func _refresh_points() -> void:
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	if store:
		var pts: int = store.data.get("total_points", 0)
		_points_label.text = _format_number(pts)


func _on_mission_available_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_pinch_mission_pressed() -> void:
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	store.preselected_exercise = "pinza"
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_coordination_pressed() -> void:
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	store.preselected_exercise = "coordinacion_3d"
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_locked_pressed() -> void:
	_show_toast("Próximamente")


func _on_locked_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_show_toast("Próximamente")
	elif event is InputEventScreenTouch and event.pressed:
		_show_toast("Próximamente")


func _show_toast(msg: String) -> void:
	_toast_label.text = msg
	if _toast_tween and _toast_tween.is_running():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_label.modulate.a = 1.0
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
