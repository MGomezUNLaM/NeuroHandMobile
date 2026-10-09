extends Node

## Gestor global de desplazamiento táctil e inercia (Smooth Touch & Drag Scroll)
## Permite deslizar la pantalla con el dedo o mouse en cualquier ScrollContainer,
## evitando clics accidentales en botones y agregando inercia cinética fluida.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_scan_and_setup(get_tree().root)


func _scan_and_setup(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is ScrollContainer:
		_attach_helper(node as ScrollContainer)
	for child in node.get_children():
		_scan_and_setup(child)


func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		_attach_helper.call_deferred(node as ScrollContainer)


func _attach_helper(scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll):
		return
	if scroll.has_node("TouchScrollHelper"):
		return
	
	var helper := TouchScrollHelper.new()
	helper.name = "TouchScrollHelper"
	scroll.add_child(helper)


class TouchScrollHelper extends Node:
	var scroll: ScrollContainer
	var _is_touching := false
	var _is_dragging := false
	var _touch_index := -1
	var _mouse_down := false

	var _start_pos := Vector2.ZERO
	var _last_pos := Vector2.ZERO
	var _start_scroll_v := 0
	var _start_scroll_h := 0

	var _velocity := Vector2.ZERO
	var _last_move_time := 0

	const DRAG_THRESHOLD: float = 8.0 # Píxeles de movimiento para iniciar arrastre
	const FRICTION: float = 7.5 # Fricción de desaceleración cinética
	const MAX_FLICK_SPEED: float = 3000.0 # Velocidad máxima de deslizamiento

	func _ready() -> void:
		scroll = get_parent() as ScrollContainer
		if scroll == null:
			set_process_input(false)
			set_process(false)
			return
		scroll.scroll_deadzone = int(DRAG_THRESHOLD)

	func _input(event: InputEvent) -> void:
		if scroll == null or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
			return

		var rect: Rect2 = scroll.get_global_rect()

		# ── TOQUE / CLIC INICIAL ──
		if event is InputEventScreenTouch:
			if event.pressed:
				if not _is_touching and rect.has_point(event.position):
					if not _is_point_on_scrollbar(event.position):
						_start_drag(event.position, event.index)
			else:
				if _is_touching and event.index == _touch_index:
					_end_drag()

		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not _is_touching and rect.has_point(event.position):
					if not _is_point_on_scrollbar(event.position):
						_mouse_down = true
						_start_drag(event.position, -1)
			else:
				if _is_touching and _mouse_down:
					_mouse_down = false
					_end_drag()

		# ── ARRASTRE / MOVIMIENTO ──
		elif event is InputEventScreenDrag:
			if _is_touching and event.index == _touch_index:
				_process_drag(event.position)

		elif event is InputEventMouseMotion:
			if _is_touching and _mouse_down:
				_process_drag(event.position)

	func _is_point_on_scrollbar(pos: Vector2) -> bool:
		var v_bar := scroll.get_v_scroll_bar()
		if v_bar != null and v_bar.is_visible_in_tree() and v_bar.get_global_rect().has_point(pos):
			return true
		var h_bar := scroll.get_h_scroll_bar()
		if h_bar != null and h_bar.is_visible_in_tree() and h_bar.get_global_rect().has_point(pos):
			return true
		return false

	func _start_drag(pos: Vector2, index: int) -> void:
		_is_touching = true
		_is_dragging = false
		_touch_index = index
		_start_pos = pos
		_last_pos = pos
		_start_scroll_v = scroll.scroll_vertical
		_start_scroll_h = scroll.scroll_horizontal
		_velocity = Vector2.ZERO
		_last_move_time = Time.get_ticks_msec()

	func _process_drag(pos: Vector2) -> void:
		var diff := pos - _start_pos
		var now := Time.get_ticks_msec()
		var dt: float = maxf(0.001, float(now - _last_move_time) / 1000.0)
		_last_move_time = now

		var can_v := (scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
		var can_h := (scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)

		if not _is_dragging:
			var moved_enough := false
			if can_v and abs(diff.y) >= DRAG_THRESHOLD:
				moved_enough = true
			elif can_h and abs(diff.x) >= DRAG_THRESHOLD:
				moved_enough = true

			if moved_enough:
				_is_dragging = true
				_cancel_button_focus()

		if _is_dragging:
			if can_v:
				scroll.scroll_vertical = _start_scroll_v - int(diff.y)
				var inst_vy := (pos.y - _last_pos.y) / dt
				_velocity.y = lerpf(_velocity.y, inst_vy, 0.45)

			if can_h:
				scroll.scroll_horizontal = _start_scroll_h - int(diff.x)
				var inst_vx := (pos.x - _last_pos.x) / dt
				_velocity.x = lerpf(_velocity.x, inst_vx, 0.45)

			_last_pos = pos
			get_viewport().set_input_as_handled()

	func _end_drag() -> void:
		_is_touching = false
		if _is_dragging:
			get_viewport().set_input_as_handled()
			_cancel_button_focus()
			_velocity.x = clampf(_velocity.x, -MAX_FLICK_SPEED, MAX_FLICK_SPEED)
			_velocity.y = clampf(_velocity.y, -MAX_FLICK_SPEED, MAX_FLICK_SPEED)
		else:
			_velocity = Vector2.ZERO

	func _cancel_button_focus() -> void:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()

	func _process(delta: float) -> void:
		if not _is_touching and is_instance_valid(scroll) and scroll.is_visible_in_tree():
			if _velocity.length_squared() > 100.0:
				var can_v := (scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
				var can_h := (scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)

				if can_v and abs(_velocity.y) > 10.0:
					var next_v := scroll.scroll_vertical - int(_velocity.y * delta)
					var prev_v := scroll.scroll_vertical
					scroll.scroll_vertical = next_v
					if scroll.scroll_vertical == prev_v:
						_velocity.y = 0.0
					else:
						_velocity.y = lerpf(_velocity.y, 0.0, FRICTION * delta)

				if can_h and abs(_velocity.x) > 10.0:
					var next_h := scroll.scroll_horizontal - int(_velocity.x * delta)
					var prev_h := scroll.scroll_horizontal
					scroll.scroll_horizontal = next_h
					if scroll.scroll_horizontal == prev_h:
						_velocity.x = 0.0
					else:
						_velocity.x = lerpf(_velocity.x, 0.0, FRICTION * delta)
			else:
				_velocity = Vector2.ZERO
