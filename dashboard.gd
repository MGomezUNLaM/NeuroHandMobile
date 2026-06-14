extends Control

## Señal para pedirle al shell que cambie de pestaña.
signal request_tab_change(index: int)

const BOB_UP := 22.0
const BOB_DOWN := 16.0
const SWAY_X := 12.0
const TILT_DEG := 5.0
const DESIGN_SIZE := Vector2(1080.0, 2340.0)
const CHART_BAR_BEST := Color(0.18, 0.9, 0.78, 1)
const CHART_BAR_LAST := Color(0.95, 0.72, 0.28, 1)
const CHART_TRACK_COLOR := Color(0.04, 0.1, 0.2, 0.85)

@onready var _main_column: VBoxContainer = $MainColumn
@onready var _start_button: Button = %StartButton
@onready var _mini_mascot_pivot: Control = %MiniMascotPivot
@onready var _mini_robot: TextureRect = %MiniRobot
@onready var _mascot_glow: Panel = %MascotGlow

@onready var _points_value: Label = %PointsValue
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _xp_label: Label = %XPLabel
@onready var _level_num: Label = %LevelNum
@onready var _objective_bar: ProgressBar = %ObjectiveBar
@onready var _objective_count: Label = %ObjectiveCount

var _mini_base_position := Vector2.ZERO


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	await get_tree().process_frame
	_apply_mobile_ui_scale()
	await get_tree().process_frame
	_refresh_dashboard()
	_setup_mascot_animation()


func _store() -> PlayerSessionStore:
	return get_node("/root/SessionStore") as PlayerSessionStore


func _on_start_pressed() -> void:
	request_tab_change.emit(1)  # Ir a pestaña Misiones


func _refresh_dashboard() -> void:
	var store: PlayerSessionStore = _store()
	var player_data: Dictionary = store.data
	_points_value.text = _format_number(int(player_data.get("total_points", 0)))
	var xp: int = int(player_data.get("xp", 0))
	var max_xp: int = PlayerSessionStore.MAX_XP_PER_LEVEL
	_xp_bar.max_value = float(max_xp)
	_xp_bar.value = float(xp)
	_xp_label.text = "%s / %s XP" % [_format_number(xp), _format_number(max_xp)]
	_level_num.text = str(int(player_data.get("level", 1)))
	var weekly: int = store.get_sessions_this_week()
	_objective_bar.max_value = float(PlayerSessionStore.WEEKLY_GOAL)
	_objective_bar.value = float(weekly)
	_objective_count.text = "%d / %d" % [weekly, PlayerSessionStore.WEEKLY_GOAL]
	pass





func _setup_mascot_animation() -> void:
	if _mini_mascot_pivot == null or _mini_robot == null:
		return
	_mini_base_position = _mini_mascot_pivot.position
	_mini_robot.pivot_offset = _mini_robot.size * 0.5
	_mini_mascot_pivot.pivot_offset = _mini_mascot_pivot.size * 0.5
	if _mascot_glow:
		_mascot_glow.pivot_offset = _mascot_glow.size * 0.5
	var float_y := create_tween().set_loops()
	float_y.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_y.tween_method(_set_mascot_y, _mini_base_position.y - BOB_UP, _mini_base_position.y + BOB_DOWN, 1.5)
	float_y.tween_method(_set_mascot_y, _mini_base_position.y + BOB_DOWN, _mini_base_position.y - BOB_UP, 1.5)
	var sway_x := create_tween().set_loops()
	sway_x.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_x.tween_method(_set_mascot_x, _mini_base_position.x - SWAY_X, _mini_base_position.x + SWAY_X, 2.2)
	sway_x.tween_method(_set_mascot_x, _mini_base_position.x + SWAY_X, _mini_base_position.x - SWAY_X, 2.2)
	var tilt := create_tween().set_loops()
	tilt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tilt.tween_property(_mini_mascot_pivot, "rotation", deg_to_rad(-TILT_DEG), 1.8)
	tilt.tween_property(_mini_mascot_pivot, "rotation", deg_to_rad(TILT_DEG), 1.8)
	var breathe := create_tween().set_loops()
	breathe.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(_mini_robot, "scale", Vector2(1.05, 1.05), 1.25)
	breathe.tween_property(_mini_robot, "scale", Vector2(0.95, 0.95), 1.25)
	if _mascot_glow:
		var pulse := create_tween().set_loops()
		pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_mascot_glow, "modulate:a", 0.5, 1.4)
		pulse.tween_property(_mascot_glow, "modulate:a", 1.0, 1.4)


func _set_mascot_y(y: float) -> void:
	var p := _mini_mascot_pivot.position
	p.y = y
	_mini_mascot_pivot.position = p


func _set_mascot_x(x: float) -> void:
	var p := _mini_mascot_pivot.position
	p.x = x
	_mini_mascot_pivot.position = p


func _format_number(value: int) -> String:
	var text := str(value)
	if text.length() <= 3:
		return text
	var parts: PackedStringArray = []
	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	if not text.is_empty():
		parts.insert(0, text)
	return ",".join(parts)


func _apply_mobile_ui_scale() -> void:
	if not _is_mobile_device():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y < 100.0:
		return
	var scale_factor := maxf(
		viewport_size.x / DESIGN_SIZE.x,
		viewport_size.y / DESIGN_SIZE.y
	)
	scale_factor = maxf(scale_factor, 1.12)
	scale_factor = clampf(scale_factor, 1.0, 1.35)
	if scale_factor <= 1.01:
		return
	_scale_ui_tree(_main_column, scale_factor)


func _is_mobile_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or DisplayServer.is_touchscreen_available()


func _scale_ui_tree(node: Node, factor: float) -> void:
	if node is Control:
		var control := node as Control
		var min_size := control.custom_minimum_size
		if min_size != Vector2.ZERO:
			control.custom_minimum_size = min_size * factor
	if node is Label:
		var label := node as Label
		var font_size := label.get_theme_font_size(&"font_size")
		if font_size > 0:
			label.add_theme_font_size_override(&"font_size", int(round(font_size * factor)))
	elif node is Button:
		var button := node as Button
		var font_size := button.get_theme_font_size(&"font_size")
		if font_size > 0:
			button.add_theme_font_size_override(&"font_size", int(round(font_size * factor)))
		var icon_width := button.get_theme_constant(&"icon_max_width")
		if icon_width > 0:
			button.add_theme_constant_override(&"icon_max_width", int(round(icon_width * factor)))
	for child in node.get_children():
		_scale_ui_tree(child, factor)
