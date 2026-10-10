extends Area2D

signal passed_by_player
signal player_crashed

const PILLAR_W := 78.0
const PIPE_TEX_H := 480.0

var speed := 200.0
var gap_y := 400.0
var gap_size := 370.0
var screen_h := 800.0

var _scored := false

func setup(g_y: float, g_size: float, scr_h: float, spd: float) -> void:
	gap_y = g_y
	gap_size = g_size
	screen_h = scr_h
	speed = spd

	var top_h := maxf(0.0, gap_y - gap_size / 2.0)
	var bot_y := minf(screen_h, gap_y + gap_size / 2.0)
	var bot_h := maxf(0.0, screen_h - bot_y)

	# Tubo Superior (Sprite2D invertido verticalmente con flip_v = true)
	# Su parte inferior toca exactamente top_h, y se extiende hacia arriba pasando el techo
	var top_pipe: Sprite2D = $TopPipe
	if top_pipe != null:
		var scale_top := maxf(1.0, (top_h + 400.0) / PIPE_TEX_H)
		top_pipe.scale = Vector2(1.0, scale_top)
		top_pipe.position = Vector2(-PILLAR_W / 2.0, top_h - (PIPE_TEX_H * scale_top))

	# Colisión Superior
	if top_h > 0:
		var top_shape := RectangleShape2D.new()
		top_shape.size = Vector2(PILLAR_W - 6.0, top_h + 400.0)
		$TopCollision.shape = top_shape
		$TopCollision.position = Vector2(0, (top_h - 400.0) / 2.0)
		$TopCollision.disabled = false
	else:
		$TopCollision.disabled = true

	# Tubo Inferior (Sprite2D normal, su parte superior empieza en bot_y y se extiende hacia abajo)
	var bot_pipe: Sprite2D = $BottomPipe
	if bot_pipe != null:
		var scale_bot := maxf(1.0, (bot_h + 400.0) / PIPE_TEX_H)
		bot_pipe.scale = Vector2(1.0, scale_bot)
		bot_pipe.position = Vector2(-PILLAR_W / 2.0, bot_y)

	# Colisión Inferior
	if bot_h > 0:
		var bot_shape := RectangleShape2D.new()
		bot_shape.size = Vector2(PILLAR_W - 6.0, bot_h + 400.0)
		$BottomCollision.shape = bot_shape
		$BottomCollision.position = Vector2(0, bot_y + (bot_h + 400.0) / 2.0)
		$BottomCollision.disabled = false
	else:
		$BottomCollision.disabled = true

	# Zona de Puntuación (en el espacio entre tubos)
	var score_shape := RectangleShape2D.new()
	score_shape.size = Vector2(24.0, gap_size)
	$ScoreArea/CollisionShape2D.shape = score_shape
	$ScoreArea/CollisionShape2D.position = Vector2(0, gap_y)


func _physics_process(delta: float) -> void:
	position.x -= speed * delta
	if position.x < -120.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_crashed.emit()


func _on_score_area_body_entered(body: Node2D) -> void:
	if not _scored and body.is_in_group("player"):
		_scored = true
		passed_by_player.emit()
