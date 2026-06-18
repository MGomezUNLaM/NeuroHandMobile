extends Area2D

signal passed_by_player
signal player_crashed

const PILLAR_W := 78.0
const CAP_H := 24.0
const CAP_W := 72.0 # PILLAR_W + 12

var speed := 200.0
var gap_y := 400.0
var gap_size := 340.0
var screen_h := 800.0

var _scored := false

func _ready() -> void:
	pass

func setup(g_y: float, g_size: float, scr_h: float, spd: float) -> void:
	gap_y = g_y
	gap_size = g_size
	screen_h = scr_h
	speed = spd
	
	var overdraw := 2000.0
	
	var top_h := gap_y - gap_size / 2.0
	var top_h_extended := top_h + overdraw
	var bot_y := gap_y + gap_size / 2.0
	var bot_h := screen_h - bot_y
	var bot_h_extended := bot_h + overdraw

	# Top Pillar Shape
	var top_shape := RectangleShape2D.new()
	top_shape.size = Vector2(PILLAR_W, top_h_extended)
	$TopCollision.shape = top_shape
	$TopCollision.position = Vector2(0, top_h - top_h_extended / 2.0)
	
	# Bottom Pillar Shape
	var bot_shape := RectangleShape2D.new()
	bot_shape.size = Vector2(PILLAR_W, bot_h_extended)
	$BottomCollision.shape = bot_shape
	$BottomCollision.position = Vector2(0, bot_y + bot_h_extended / 2.0)
	
	# Score Area
	var score_shape := RectangleShape2D.new()
	score_shape.size = Vector2(20.0, screen_h + overdraw)
	$ScoreArea/CollisionShape2D.shape = score_shape
	$ScoreArea/CollisionShape2D.position = Vector2(0, screen_h / 2.0)
	
	# Configurar NinePatchRects visuales
	var top_pipe: NinePatchRect = $TopPipe
	if top_pipe:
		top_pipe.size = Vector2(PILLAR_W, top_h_extended)
		top_pipe.position = Vector2(-PILLAR_W / 2.0, top_h)
		top_pipe.scale = Vector2(1, -1) # Invertimos el tubo para que la tapa apunte hacia abajo
		
	var bot_pipe: NinePatchRect = $BottomPipe
	if bot_pipe:
		bot_pipe.size = Vector2(PILLAR_W, bot_h_extended)
		bot_pipe.position = Vector2(-PILLAR_W / 2.0, bot_y)
		bot_pipe.scale = Vector2(1, 1)

func _physics_process(delta: float) -> void:
	position.x -= speed * delta
	if position.x < -100.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_crashed.emit()

func _on_score_area_body_entered(body: Node2D) -> void:
	if not _scored and body.is_in_group("player"):
		_scored = true
		passed_by_player.emit()
