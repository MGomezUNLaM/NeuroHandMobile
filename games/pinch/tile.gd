extends ColorRect

signal missed(tile_node)

var speed: float = 150.0
var column_index: int = 0
var is_active: bool = true

func _ready() -> void:
	color = Color(0.1, 0.1, 0.1, 1.0) # Classic black tile

func _process(delta: float) -> void:
	if not is_active:
		return
		
	position.y += speed * delta
	
	# Asumiendo alto de pantalla aprox 800
	if position.y > 850:
		is_active = false
		missed.emit(self)
		_play_miss_animation()

func _play_miss_animation() -> void:
	color = Color(1.0, 0.2, 0.2, 1.0) # Rojo claro
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)

func hit() -> void:
	is_active = false
	color = Color(0.2, 1.0, 0.4, 1.0) # Verde vibrante
	var tween = create_tween()
	# Para escalar bien desde el centro, ajustamos el pivot
	pivot_offset = size / 2.0
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(queue_free)
