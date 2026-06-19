extends Control

signal game_over
signal score_updated(new_score: int)

var tile_scene = preload("res://games/pinch/tile.tscn")

@onready var hit_zone = $HitZone
@onready var tile_container = $TileContainer
@onready var column_highlights = [
	$Background/Col0, $Background/Col1, $Background/Col2, $Background/Col3
]
@onready var score_label = $UI/ScoreLabel
@onready var timer = $SpawnTimer

var score: int = 0
var active_tiles: Array[Node] = []
var _is_pinching: bool = false
var _fsr_threshold: float = 15.0  # Mínimo de FSR para contar como pinch

func _ready() -> void:
	BleManager.fsr_updated.connect(_on_fsr_updated)
	timer.timeout.connect(_spawn_tile)

func _exit_tree() -> void:
	if BleManager.fsr_updated.is_connected(_on_fsr_updated):
		BleManager.fsr_updated.disconnect(_on_fsr_updated)

func _process(_delta: float) -> void:
	# Ajustar layout de columnas dinámicamente si la pantalla cambia
	var col_w = size.x / 4.0
	for i in range(4):
		var col = column_highlights[i]
		col.position.x = i * col_w
		col.size.x = col_w

func _spawn_tile() -> void:
	var tile = tile_scene.instantiate()
	var col_idx = randi() % 4
	tile.column_index = col_idx
	
	var col_w = size.x / 4.0
	var spawn_x = (col_w * col_idx) + (col_w / 2.0) - 40.0
	tile.position = Vector2(spawn_x, -150)
	
	tile.missed.connect(_on_tile_missed)
	tile_container.add_child(tile)
	active_tiles.append(tile)

func _on_tile_missed(tile: Node) -> void:
	if tile in active_tiles:
		active_tiles.erase(tile)

func _on_fsr_updated(fsr: float) -> void:
	if fsr >= _fsr_threshold and not _is_pinching:
		_is_pinching = true
		_handle_pinch()
	elif fsr < _fsr_threshold and _is_pinching:
		_is_pinching = false

func _handle_pinch() -> void:
	var fingers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if "last_fingers_value" in BleManager:
		fingers = BleManager.last_fingers_value
	
	var max_flex: float = -1.0
	var max_idx: int = -1
	for i in range(4):
		if fingers[i] > max_flex:
			max_flex = fingers[i]
			max_idx = i
			
	if max_idx >= 0 and max_idx <= 3:
		_tap_column(max_idx)

func _tap_column(col_idx: int) -> void:
	var col_rect = column_highlights[col_idx]
	var tw = create_tween()
	col_rect.color.a = 0.4
	tw.tween_property(col_rect, "color:a", 0.05, 0.2)
	
	var hit_y_top = 0.0 # Permitir golpear la tecla en cualquier momento antes de que caiga
	var hit_y_bot = hit_zone.position.y + hit_zone.size.y + 100
	
	var oldest_tile: Node = null
	var lowest_y: float = -9999.0
	
	# Encontrar la ficha más baja (la más vieja) en toda la pantalla
	for tile in active_tiles:
		if tile.is_active:
			var ty = tile.position.y + tile.size.y
			if ty >= hit_y_top and tile.position.y <= hit_y_bot:
				if ty > lowest_y:
					lowest_y = ty
					oldest_tile = tile
					
	if oldest_tile != null:
		if oldest_tile.column_index == col_idx:
			# Acierto: la ficha más vieja estaba en esta columna
			oldest_tile.hit()
			active_tiles.erase(oldest_tile)
			score += 10
			score_label.text = str(score)
			score_updated.emit(score)
			if has_node("HitAudio"):
				$HitAudio.play()
		else:
			# Error: tocó una columna equivocada para la ficha actual
			oldest_tile.is_active = false
			if oldest_tile.has_method("_play_miss_animation"):
				oldest_tile._play_miss_animation()
			active_tiles.erase(oldest_tile)

func _on_back_pressed() -> void:
	game_over.emit()
	queue_free()
