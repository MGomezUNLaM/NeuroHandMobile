extends Control

signal score_updated(score: int)

@onready var _player: CharacterBody2D = $World/Player
@onready var _pillars_container: Node2D = $World/Pillars
@onready var _world: Node2D = $World
@onready var _bg_container: Node2D = $World/BackgroundContainer
@onready var _ground_container: Node2D = $World/GroundContainer
@onready var _score_label: Label = get_node_or_null("ScoreLabel")

var _is_running := false
var _is_thrusting := false
var _score := 0
var _pillar_timer := 0.0

const GRAVITY := 850.0
const FLAP_VEL := -450.0
const THRUST_FORCE := -1450.0
const MAX_FALL := 800.0
const PILLAR_SPEED := 200.0
const PILLAR_INTERVAL := 2.2
const PILLAR_GAP := 350.0

const BG_WIDTH := 456.0
const BG_HEIGHT := 811.3
const GROUND_WIDTH := 504.0
const GROUND_H := 140.0

var _pillar_scene = preload("res://games/flappy/space_pillar.tscn")


func _ready() -> void:
	_world.position = Vector2.ZERO
	_world.scale = Vector2.ONE
	_update_layout()
	_player.position = Vector2(_get_player_start_x(), _get_ground_y() * 0.45)


func _get_ground_y() -> float:
	var h: float = size.y if size.y > 100.0 else 800.0
	return h - GROUND_H


func _get_player_start_x() -> float:
	var w: float = size.x if size.x > 100.0 else 450.0
	return clampf(w * 0.25, 120.0, 180.0)


func _update_layout() -> void:
	var gy := _get_ground_y()
	if _ground_container != null:
		_ground_container.position.y = gy
	if _bg_container != null:
		# Alinear la base del skyline exactamente con el inicio del piso
		_bg_container.position.y = gy - BG_HEIGHT


func start_game() -> void:
	_is_running = true
	_score = 0
	_update_layout()
	_player.position = Vector2(_get_player_start_x(), _get_ground_y() * 0.45)
	_player.velocity = Vector2.ZERO
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = 0.0
	_update_score_display()
	score_updated.emit(_score)
	var w: float = size.x if size.x > 100.0 else 500.0
	_spawn_pillar_at(w + 40.0)


func restart_run() -> void:
	_score = 0
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = 0.0
	_player.velocity.y = -200.0
	_update_score_display()
	score_updated.emit(_score)
	var w: float = size.x if size.x > 100.0 else 500.0
	_spawn_pillar_at(w + 40.0)


func end_game() -> void:
	_is_running = false


func set_thrust(thrust: bool) -> void:
	_is_thrusting = thrust


func _update_score_display() -> void:
	if _score_label != null:
		_score_label.text = str(_score)


func _process(delta: float) -> void:
	_world.position = Vector2.ZERO
	_world.scale = Vector2.ONE
	_update_layout()
	var gy := _get_ground_y()
	var w: float = size.x if size.x > 100.0 else 500.0

	# Scroll infinito del fondo
	if _bg_container != null:
		var bg_speed := 30.0 if _is_running else 15.0
		_bg_container.position.x -= bg_speed * delta
		if _bg_container.position.x <= -BG_WIDTH:
			_bg_container.position.x += BG_WIDTH

	# Scroll infinito del piso
	if _ground_container != null:
		var ground_speed := PILLAR_SPEED if _is_running else 60.0
		_ground_container.position.x -= ground_speed * delta
		if _ground_container.position.x <= -GROUND_WIDTH:
			_ground_container.position.x += GROUND_WIDTH

	if not _is_running:
		_player.position.y = (gy * 0.45) + sin(Time.get_ticks_msec() * 0.003) * 15.0
		_player.rotation = sin(Time.get_ticks_msec() * 0.002) * 0.1
		return

	# Física del pájaro
	if _is_thrusting:
		_player.velocity.y += THRUST_FORCE * delta
	else:
		_player.velocity.y += GRAVITY * delta
		
	_player.velocity.y = clampf(_player.velocity.y, FLAP_VEL * 1.5, MAX_FALL)
	
	_player.move_and_collide(_player.velocity * delta)
	
	if _player.velocity.y < 0:
		_player.rotation = lerp_angle(_player.rotation, -0.4, delta * 15.0)
	else:
		var target := clampf(_player.velocity.y / 500.0, 0.0, 0.6)
		_player.rotation = lerp_angle(_player.rotation, target, delta * 6.0)

	# Límites de pantalla (Piso y Techo)
	if _player.position.y >= gy - 16.0:
		_player.position.y = gy - 16.0
		_player.velocity.y = 0.0
	elif _player.position.y <= 16.0:
		_player.position.y = 16.0
		_player.velocity.y = 0.0

	# Spawn de Pilares
	_pillar_timer += delta
	if _pillar_timer >= PILLAR_INTERVAL:
		_pillar_timer = 0.0
		_spawn_pillar_at(w + 60.0)


func _spawn_pillar_at(spawn_x: float) -> void:
	var gy := _get_ground_y()
	var margin := 100.0
	var min_y := PILLAR_GAP / 2.0 + margin
	var max_y := (gy - 40.0) - PILLAR_GAP / 2.0
	var g_y := randf_range(min_y, max_y)
	
	var pillar = _pillar_scene.instantiate()
	_pillars_container.add_child(pillar)
	pillar.position = Vector2(spawn_x, 0)
	pillar.setup(g_y, PILLAR_GAP, gy, PILLAR_SPEED)
	
	pillar.passed_by_player.connect(_on_pillar_passed)
	pillar.player_crashed.connect(_on_pillar_crashed)


func _on_pillar_passed() -> void:
	_score += 1
	_update_score_display()
	score_updated.emit(_score)


func _on_pillar_crashed() -> void:
	restart_run()
