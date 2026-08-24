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

# Umbral de flexión requerido en el dedo objetivo para considerar la pinza correcta (30%)
@export var finger_flex_threshold: float = 30.0
@export var fsr_threshold: float = 15.0  # Mínimo de FSR para contar como pinch

func _on_tile_missed(tile: Node) -> void:
	if tile in active_tiles:
		active_tiles.erase(tile)

func _on_fsr_updated(fsr: float) -> void:
	if fsr >= fsr_threshold and not _is_pinching:
		_is_pinching = true
		_handle_pinch()
	elif fsr < fsr_threshold and _is_pinching:
		_is_pinching = false

func _handle_pinch() -> void:
	# Dedos correspondientes a cada columna:
	# Col 0: Índice, Col 1: Medio, Col 2: Anular, Col 3: Meñique
	var fingers: Array[float] = [BleManager.indice, BleManager.medio, BleManager.anular, BleManager.menique]
	
	# 1. Obtener la ficha objetivo (la más baja / prioritaria en pantalla)
	var target_tile := _get_target_tile()
	
	if target_tile != null:
		var target_col: int = target_tile.column_index
		var target_finger_flex: float = fingers[target_col] if target_col >= 0 and target_col < fingers.size() else 0.0
		
		# REGLA 1: Si el dedo de la columna objetivo alcanza al menos el 30% de flexión -> ACIERTO
		if target_finger_flex >= finger_flex_threshold:
			_hit_tile(target_tile, target_col)
			return
		
		# REGLA 2: Si el dedo objetivo no llegó al 30%, verificar si flexionó OTRO dedo >= 30% (error de dedo)
		var other_col := -1
		var other_max := -1.0
		for i in range(4):
			if i != target_col and fingers[i] >= finger_flex_threshold and fingers[i] > other_max:
				other_max = fingers[i]
				other_col = i
				
		if other_col >= 0:
			# El paciente flexionó claramente otro dedo
			_miss_tile(target_tile, other_col)
			return
			
		# REGLA 3: Tolerancia (si sólo se detectó presión FSR o flexión parcial en el dedo objetivo)
		if target_finger_flex >= 10.0 or (fingers[0] < 5.0 and fingers[1] < 5.0 and fingers[2] < 5.0 and fingers[3] < 5.0):
			_hit_tile(target_tile, target_col)
		else:
			_miss_tile(target_tile, target_col)
	else:
		# No hay fichas en la zona, solo iluminar la columna del dedo con mayor flexión como feedback
		var max_col = _get_max_finger_idx(fingers)
		if max_col >= 0:
			_flash_column(max_col, Color(0, 0, 0, 0.2))

## Busca la ficha activa que debe ser golpeada (con compensación de delay)
func _get_target_tile() -> Node:
	var hit_y_top = 0.0 # Ventana generosa: permite golpear antes o después
	var hit_y_bot = hit_zone.position.y + hit_zone.size.y + 120.0 # Margen de tolerancia de retraso
	
	var oldest_tile: Node = null
	var lowest_y: float = -9999.0
	for tile in active_tiles:
		if is_instance_valid(tile) and tile.is_active:
			var ty = tile.position.y + tile.size.y
			if ty >= hit_y_top and tile.position.y <= hit_y_bot:
				if ty > lowest_y:
					lowest_y = ty
					oldest_tile = tile
	return oldest_tile

func _get_max_finger_idx(fingers: Array[float]) -> int:
	var max_val := -1.0
	var max_idx := -1
	for i in range(fingers.size()):
		if fingers[i] > max_val:
			max_val = fingers[i]
			max_idx = i
	return max_idx

func _hit_tile(tile: Node, col_idx: int) -> void:
	_flash_column(col_idx, Color(0.1, 0.8, 0.5, 0.45)) # Verde brillante
	tile.hit()
	active_tiles.erase(tile)
	score += 10
	score_label.text = str(score)
	score_updated.emit(score)
	if has_node("HitAudio"):
		$HitAudio.play()

func _miss_tile(tile: Node, col_idx: int) -> void:
	_flash_column(col_idx, Color(0.9, 0.2, 0.2, 0.4)) # Destello rojo
	tile.is_active = false
	if tile.has_method("_play_miss_animation"):
		tile._play_miss_animation()
	active_tiles.erase(tile)

func _flash_column(col_idx: int, color: Color) -> void:
	if col_idx < 0 or col_idx >= column_highlights.size():
		return
	var col_rect = column_highlights[col_idx]
	var tw = create_tween()
	col_rect.color = color
	tw.tween_property(col_rect, "color", Color(0, 0, 0, 0.05), 0.25)

func _on_back_pressed() -> void:
	game_over.emit()
	queue_free()
