extends Node3D

func animate_to(is_closed: bool) -> void:
	if not is_inside_tree():
		return
	var target_x = 1.5 if is_closed else -1.5
	var target_rot_y = -20.0 if is_closed else 20.0
	
	var tween = create_tween()
	if not tween:
		return
	tween.set_parallel(true)
	
	var target_pos = self.position
	target_pos.x = target_x
	
	var target_rot = self.rotation_degrees
	target_rot.y = target_rot_y
	
	if is_closed:
		tween.tween_property(self, "position", target_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "rotation_degrees", target_rot, 0.25)
	else:
		tween.tween_property(self, "position", target_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "rotation_degrees", target_rot, 0.35)
