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


func _set_preselected(exercise: String, keys: Array) -> void:
	var store := get_node("/root/SessionStore") as PlayerSessionStore
	if not store:
		return
	store.preselected_exercise = exercise
	store.preselected_difficulty = "medio"
	store.preselected_difficulty_factor = 1.0
	store.preselected_activity_id = ""
	if has_node("/root/ApiClient"):
		var api = get_node("/root/ApiClient")
		for act in api.active_activities:
			var t: String = str(act.get("type", "")).to_lower()
			var n: String = str(act.get("name", "")).to_lower()
			for k in keys:
				var k_lower: String = str(k).to_lower()
				if t.contains(k_lower) or n.contains(k_lower):
					store.preselected_difficulty = act.get("difficulty", "medio")
					store.preselected_difficulty_factor = float(act.get("difficulty_factor", 1.0))
					store.preselected_activity_id = str(act.get("sessionActivityId", act.get("id", "")))
					break


func _on_mission_available_pressed() -> void:
	_set_preselected("flexion", ["flappy", "flexion", "arcade", "pajaro"])
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_functional_pressed() -> void:
	_set_preselected("flexion_constante", ["botella", "flexion_constante", "vaso", "bottle"])
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_pinch_mission_pressed() -> void:
	_set_preselected("pinza", ["pinza", "piano", "pinch"])
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_coordination_pressed() -> void:
	_set_preselected("coordinacion_3d", ["basket", "coordinacion", "coordinacion_3d"])
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
