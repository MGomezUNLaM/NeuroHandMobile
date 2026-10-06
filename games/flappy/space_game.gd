extends Control

signal score_updated(score: int)

const GW := 600.0
const GH := 800.0
const GROUND_Y := 688.0

const BG_SPEED := 50.0
const BG_WIDTH := 449.65
const GROUND_SPEED := 200.0
const GROUND_WIDTH := 336.0

@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $World/Player
@onready var _pillars_container: Node2D = $World/Pillars
@onready var _bg_container: Node2D = $World/BackgroundContainer
@onready var _ground_container: Node2D = $World/GroundContainer

var _is_running := false
var _is_thrusting := false
var _score := 0
var _pillar_timer := 0.0

const GRAVITY := 850.0
const FLAP_VEL := -420.0
const THRUST_FORCE := -1400.0
const MAX_FALL := 750.0
const PILLAR_SPEED := 200.0
const PILLAR_INTERVAL := 2.2
const PILLAR_GAP := 350.0

var _pillar_scene = preload("res://games/flappy/space_pillar.tscn")

func _ready() -> void:
	_player.position = Vector2(150.0, (GROUND_Y / 2.0) - 20.0)

func start_game() -> void:
	_is_running = true
	_score = 0
	_player.position = Vector2(150.0, (GROUND_Y / 2.0) - 20.0)
	_player.velocity = Vector2.ZERO
	_player.rotation = 0.0
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = PILLAR_INTERVAL - 0.8
	score_updated.emit(_score)

func restart_run() -> void:
	_score = 0
	for child in _pillars_container.get_children():
		child.queue_free()
	_pillar_timer = PILLAR_INTERVAL - 0.8
	_player.position.y = (GROUND_Y / 2.0) - 20.0
	_player.velocity.y = -200.0
	_player.rotation = 0.0
	score_updated.emit(_score)

func end_game() -> void:
	_is_running = false

func set_thrust(thrust: bool) -> void:
	_is_thrusting = thrust

func trigger_action() -> void:
	if _is_running:
		_player.velocity.y = FLAP_VEL

func _process(delta: float) -> void:
	# Escalado dinámico al tamaño real del Control (Letterbox)
	var scale_factor := 1.0
	if size.x > 0 and size.y > 0:
		scale_factor = minf(size.x / GW, size.y / GH)
	_world.scale = Vector2(scale_factor, scale_factor)
	_world.position.x = (size.x - (GW * scale_factor)) / 2.0
	_world.position.y = (size.y - (GH * scale_factor)) / 2.0

	# Scroll de fondo panorámico
	for bg_sprite in _bg_container.get_children():
		bg_sprite.position.x -= BG_SPEED * delta
		if bg_sprite.position.x <= -BG_WIDTH:
			bg_sprite.position.x += BG_WIDTH * 3.0

	# Scroll del suelo
	for ground_sprite in _ground_container.get_children():
		ground_sprite.position.x -= GROUND_SPEED * delta
		if ground_sprite.position.x <= -GROUND_WIDTH:
			ground_sprite.position.x += GROUND_WIDTH * 3.0

	if not _is_running:
		_player.position.y = (GROUND_Y / 2.0) - 20.0 + sin(Time.get_ticks_msec() * 0.003) * 15.0
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
		_player.rotation = lerp_angle(_player.rotation, -0.35, delta * 15.0)
	else:
		var target := clampf(_player.velocity.y / 500.0, 0.0, 0.6)
		_player.rotation = lerp_angle(_player.rotation, target, delta * 6.0)

	# Límites: Techo y Piso (suelo visual en GROUND_Y)
	if _player.position.y >= GROUND_Y - 16.0:
		_player.position.y = GROUND_Y - 16.0
		_player.velocity.y = 0.0
	elif _player.position.y <= 16.0:
		_player.position.y = 16.0
		_player.velocity.y = 0.0

	# Spawn de columnas
	_pillar_timer += delta
	if _pillar_timer >= PILLAR_INTERVAL:
		_pillar_timer = 0.0
		_spawn_pillar()

func _spawn_pillar() -> void:
	var margin := 90.0
	var min_y := PILLAR_GAP / 2.0 + margin
	var max_y := GROUND_Y - margin - PILLAR_GAP / 2.0
	var g_y := randf_range(min_y, max_y)
	
	var pillar = _pillar_scene.instantiate()
	_pillars_container.add_child(pillar)
	pillar.position = Vector2(GW + 40.0, 0.0)
	pillar.setup(g_y, PILLAR_GAP, GROUND_Y, PILLAR_SPEED)
	
	pillar.passed_by_player.connect(_on_pillar_passed)
	pillar.player_crashed.connect(_on_pillar_crashed)

func _on_pillar_passed() -> void:
	_score += 1
	score_updated.emit(_score)

func _on_pillar_crashed() -> void:
	restart_run()
