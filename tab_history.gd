extends Control

const DESIGN_SIZE := Vector2(1080.0, 2340.0)

@onready var _main_column: VBoxContainer = $MainColumn
@onready var _stats_sessions: Label = %StatsSessions
@onready var _stats_time: Label = %StatsTime
@onready var _stats_score: Label = %StatsScore
@onready var _donut_apertura: Control = %DonutApertura
@onready var _donut_agarre: Control = %DonutAgarre
@onready var _donut_pinza: Control = %DonutPinza
@onready var _donut_coord: Control = %DonutCoord

func _ready() -> void:
	await get_tree().process_frame
	_apply_mobile_ui_scale()
	await get_tree().process_frame
	_populate_data()

func _populate_data() -> void:
	var store = get_node_or_null("/root/SessionStore")
	if store == null: return
	
	var weekly = store.get_sessions_this_week()
	var total = store.get_total_sessions()
	var avg = store.get_average_taps()
	
	_stats_sessions.text = str(weekly)
	_stats_time.text = "%dh %dm" % [weekly / 2, (weekly * 15) % 60] # Mock time
	_stats_score.text = "%.0f" % avg
	
	if _donut_apertura.has_method("set_progress"):
		_donut_apertura.set_progress(80, 100, "80%", "Apertura")
		_donut_agarre.set_progress(65, 100, "65%", "Agarre")
		_donut_pinza.set_progress(70, 100, "70%", "Pinza")
		_donut_coord.set_progress(75, 100, "75%", "Coordinación")

func _apply_mobile_ui_scale() -> void:
	if not _is_mobile_device(): return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y < 100.0: return
	var scale_factor := maxf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	scale_factor = clampf(maxf(scale_factor, 1.12), 1.0, 1.35)
	if scale_factor > 1.01:
		_scale_ui_tree(_main_column, scale_factor)

func _is_mobile_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or DisplayServer.is_touchscreen_available()

func _scale_ui_tree(node: Node, factor: float) -> void:
	if node is Control:
		var ctrl := node as Control
		var min_size: Vector2 = ctrl.custom_minimum_size
		if min_size != Vector2.ZERO:
			ctrl.custom_minimum_size = min_size * factor
	if node is Label:
		var lbl := node as Label
		var fs: int = lbl.get_theme_font_size(&"font_size")
		if fs > 0:
			lbl.add_theme_font_size_override(&"font_size", int(round(fs * factor)))
	for child in node.get_children():
		_scale_ui_tree(child, factor)
