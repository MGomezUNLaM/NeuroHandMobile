extends Area2D

signal passed_by_player
signal player_crashed

const PILLAR_W := 78.0
const PIPE_TEXTURE_H := 480.0

var speed := 200.0
var gap_y := 400.0
var gap_size := 340.0
var screen_h := 800.0

var _scored := false

func setup(g_y: float, g_size: float, scr_h: float, spd: float) -> void:
	gap_y = g_y
	gap_size = g_size
	screen_h = scr_h
	speed = spd
	
	var top_h := gap_y - gap_size / 2.0
	var bot_y := gap_y + gap_size / 2.0
	
	# Top Pipe Sprite & Collision
	var top_pipe: Sprite2D = $TopPipe
	if top_pipe:
		top_pipe.position = Vector2(-PILLAR_W / 2.0, top_h - PIPE_TEXTURE_H)
		top_pipe.flip_v = true
		
	var top_shape := RectangleShape2D.new()
	var top_col_h := maxf(top_h + 200.0, 10.0)
	top_shape.size = Vector2(PILLAR_W - 8.0, top_col_h)
	$TopCollision.shape = top_shape
	$TopCollision.position = Vector2(0.0, top_h - top_col_h / 2.0)
	
	# Bottom Pipe Sprite & Collision
	var bot_pipe: Sprite2D = $BottomPipe
	if bot_pipe:
		bot_pipe.position = Vector2(-PILLAR_W / 2.0, bot_y)
		bot_pipe.flip_v = false
		
	var bot_shape := RectangleShape2D.new()
	var bot_col_h := maxf((screen_h - bot_y) + 200.0, 10.0)
	bot_shape.size = Vector2(PILLAR_W - 8.0, bot_col_h)
	$BottomCollision.shape = bot_shape
	$BottomCollision.position = Vector2(0.0, bot_y + bot_col_h / 2.0)
	
	# Score Area
	var score_shape := RectangleShape2D.new()
	score_shape.size = Vector2(24.0, gap_size)
	$ScoreArea/CollisionShape2D.shape = score_shape
	$ScoreArea/CollisionShape2D.position = Vector2(PILLAR_W / 2.0 + 10.0, gap_y)

func _physics_process(delta: float) -> void:
	position.x -= speed * delta
	if position.x < -150.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_crashed.emit()

func _on_score_area_body_entered(body: Node2D) -> void:
	if not _scored and body.is_in_group("player"):
		_scored = true
		passed_by_player.emit()
