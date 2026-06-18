extends Control

signal start_requested

@onready var _hand_sprite: AnimatedSprite2D = $CenterContainer/Panel/VBox/HBox/HandContainer/HandSprite
@onready var _bird_canvas: Control = %BirdCanvas

var _is_closed := false

func _ready() -> void:
	$Timer.start()

func setup(text: String, is_functional: bool = false) -> void:
	if has_node("%InstructionText"):
		%InstructionText.text = text
	
	if is_functional:
		if has_node("%BirdCanvas"):
			%BirdCanvas.hide()
		var arrow = get_node_or_null("CenterContainer/Panel/VBox/HBox/Arrow")
		if arrow:
			arrow.hide()
		if has_node("%BottleViewportContainer"):
			%BottleViewportContainer.show()
	else:
		if has_node("%BirdCanvas"):
			%BirdCanvas.show()
		var arrow = get_node_or_null("CenterContainer/Panel/VBox/HBox/Arrow")
		if arrow:
			arrow.show()
		if has_node("%BottleViewportContainer"):
			%BottleViewportContainer.hide()

func _on_timer_timeout() -> void:
	_is_closed = not _is_closed
	
	if is_instance_valid(_bird_canvas) and _bird_canvas.visible:
		_bird_canvas._is_closed = _is_closed
		
		var tween := create_tween()
		if _is_closed:
			_hand_sprite.play("default")
			tween.tween_property(_bird_canvas, "_bird_y", 60.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_hand_sprite.play_backwards("default")
			tween.tween_property(_bird_canvas, "_bird_y", 120.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif has_node("%BottleViewportContainer") and %BottleViewportContainer.visible:
		if _is_closed:
			_hand_sprite.play("default")
		else:
			_hand_sprite.play_backwards("default")
			
		var bottle_script = %BottleViewportContainer.get_node_or_null("SubViewport/BottlePivot")
		if bottle_script and bottle_script.has_method("animate_to"):
			bottle_script.animate_to(_is_closed)

func _on_start_pressed() -> void:
	start_requested.emit()
	hide()
