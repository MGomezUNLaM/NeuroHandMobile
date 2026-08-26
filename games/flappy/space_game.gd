extends Control

signal score_updated(score: int)

const GW := 600.0
const GH := 800.0

@onready var _player: CharacterBody2D = $World/Player
@onready var _pillars_container: Node2D = $World/Pillars
@onready var _stars_layer: Node2D = $StarsLayer
@onready var _world: Node2D = $World

var _is_running := false
var _is_thrusting := false
var _score := 0
var _pillar_timer := 0.0

const GRAVITY := 800.0
const FLAP_VEL := -450.0
const THRUST_FORCE := -1400.0
const MAX_FALL := 800.0
const PILLAR_SPEED := 200.0
const PILLAR_INTERVAL := 2.2
const PILLAR_GAP := 370.0

var _pillar_scene = preload("res://games/flappy/space_pillar.tscn")

func _ready() -> void:
	_player.position = Vector2(150, GH / 2.0)

func _generate_stars() -> void:
	pass

func start_game() -> void:
	_is_running = true
	_score = 0
	_player.position = Vector2(150, GH / 2.0)
	_player.velocity = Vector2.ZERO
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = 0.0
	score_updated.emit(_score)

func restart_run() -> void:
	_score = 0
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = 0.0
	_player.velocity.y = -200.0
	score_updated.emit(_score)

func end_game() -> void:
	_is_running = false

func set_thrust(thrust: bool) -> void:
	_is_thrusting = thrust

func _process(delta: float) -> void:
	# Escalado dinámico al tamaño real del Control (Letterbox)
	var scale_factor := 1.0
	if size.x > 0 and size.y > 0:
		scale_factor = minf(size.x / GW, size.y / GH)
	_world.scale = Vector2(scale_factor, scale_factor)
	_world.position.x = (size.x - (GW * scale_factor)) / 2.0
	_world.position.y = (size.y - (GH * scale_factor)) / 2.0

	var bg: ParallaxBackground = _world.get_node_or_null("ParallaxBackground")
	var fg: ParallaxBackground = _world.get_node_or_null("ForegroundParallax")

	if not _is_running:
		_player.position.y = GH / 2.0 + sin(Time.get_ticks_msec() * 0.003) * 15.0
		_player.rotation = sin(Time.get_ticks_msec() * 0.002) * 0.1
		if bg:
			bg.scroll_offset.x -= 20.0 * delta
		if fg:
			fg.scroll_offset.x -= 150.0 * delta
		return

	# Parallax
	if bg:
		bg.scroll_offset.x -= 100.0 * delta
	if fg:
		fg.scroll_offset.x -= 200.0 * delta

	# Física de la nave
	if _is_thrusting:
		_player.velocity.y += THRUST_FORCE * delta
	else:
		_player.velocity.y += GRAVITY * delta
		
	_player.velocity.y = clampf(_player.velocity.y, FLAP_VEL * 1.5, MAX_FALL)
	
	var collision = _player.move_and_collide(_player.velocity * delta)
	
	if _player.velocity.y < 0:
		_player.rotation = lerp_angle(_player.rotation, -0.4, delta * 15.0)
	else:
		var target := clampf(_player.velocity.y / 500.0, 0.0, 0.6)
		_player.rotation = lerp_angle(_player.rotation, target, delta * 6.0)

	# Límites de pantalla (Piso y Techo)
	if _player.position.y >= GH - 40 - 16:
		_player.position.y = GH - 40 - 16
		_player.velocity.y = 0.0
		# Piso toca, reiniciamos? Sí, para evitar arrastrarse si hay tubos.
		# restart_run()
	elif _player.position.y <= 16:
		_player.position.y = 16
		_player.velocity.y = 0.0

	# Pilares
	_pillar_timer += delta
	if _pillar_timer >= PILLAR_INTERVAL:
		_pillar_timer = 0.0
		_spawn_pillar()

func _spawn_pillar() -> void:
	var margin := 120.0
	var min_y := PILLAR_GAP / 2.0 + margin
	var max_y := GH - margin - PILLAR_GAP / 2.0
	var g_y := randf_range(min_y, max_y)
	
	var pillar = _pillar_scene.instantiate()
	_pillars_container.add_child(pillar)
	pillar.position = Vector2(GW + 50.0, 0)
	pillar.setup(g_y, PILLAR_GAP, GH, PILLAR_SPEED)
	
	pillar.passed_by_player.connect(_on_pillar_passed)
	pillar.player_crashed.connect(_on_pillar_crashed)

func _on_pillar_passed() -> void:
	_score += 1
	score_updated.emit(_score)

func _on_pillar_crashed() -> void:
	restart_run()
