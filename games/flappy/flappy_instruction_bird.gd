extends Control

var _pipe_x := 200.0
var _bird_y := 120.0
var _is_closed := false
var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	_pipe_x -= 100.0 * delta
	if _pipe_x < -60.0:
		_pipe_x = 220.0
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	
	# Fondo celeste clásico
	draw_rect(Rect2(0, 0, w, h), Color("4ec0ca"))

	# Nubes de fondo simples
	draw_circle(Vector2(50, h - 50), 30, Color(1, 1, 1, 0.5))
	draw_circle(Vector2(90, h - 40), 40, Color(1, 1, 1, 0.5))
	draw_circle(Vector2(200, h - 60), 35, Color(1, 1, 1, 0.5))
	
	# Piso clásico
	var floor_y := h - 25.0
	draw_rect(Rect2(0, floor_y, w, 25), Color("ded895"))
	draw_rect(Rect2(0, floor_y, w, 6), Color("73bf2e"))
	draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color("543847"), 3.0)
	var grid_offset = fmod(-_time * 100.0, 30.0)
	for i in range(-1, int(w / 30.0) + 2):
		var px = grid_offset + i * 30.0
		draw_line(Vector2(px, floor_y), Vector2(px - 15, h), Color("d0c678"), 2.0)

	# Tubos clásicos
	var c_base := Color("73bf2e")
	var c_light := Color("9ce659")
	var c_border := Color("543847")
	
	var gap_y := h / 2.0 - 20.0
	var gap_size := 80.0
	var pipe_w := 46.0
	
	var top_h := gap_y - gap_size/2.0
	var bot_y := gap_y + gap_size/2.0
	var bot_h := floor_y - bot_y
	
	_draw_single_pillar(self, _pipe_x, 0.0, top_h, true, pipe_w, c_base, c_light, c_border)
	_draw_single_pillar(self, _pipe_x, bot_y, bot_h, false, pipe_w, c_base, c_light, c_border)

	# Pájaro clásico
	_draw_bird(self, Vector2(50, _bird_y))

func _draw_single_pillar(c: CanvasItem, px: float, py: float, ph: float, is_top: bool, pw: float, c_base: Color, c_light: Color, c_border: Color) -> void:
	if ph <= 0: return
	var cap_h := 20.0
	var cap_y := py + ph - cap_h if is_top else py
	var body_y := py if is_top else py + cap_h
	var body_h := ph - cap_h

	if body_h > 0:
		c.draw_rect(Rect2(px, body_y, pw, body_h), c_base)
		c.draw_rect(Rect2(px + 4, body_y, 8, body_h), c_light)
		c.draw_rect(Rect2(px, body_y, pw, body_h), c_border, false, 3.0)

	var cap_w := pw + 8
	var cap_x := px - 4
	c.draw_rect(Rect2(cap_x, cap_y, cap_w, cap_h), c_base)
	c.draw_rect(Rect2(cap_x + 4, cap_y + 4, cap_w - 8, cap_h - 8), c_light)
	c.draw_rect(Rect2(cap_x, cap_y, cap_w, cap_h), c_border, false, 3.0)

func _draw_bird(c: CanvasItem, pos: Vector2) -> void:
	c.draw_set_transform(pos, -0.4 if _is_closed else 0.4, Vector2.ONE)

	var c_body := Color("f7cd46")
	var c_wing := Color("ffffff") if _is_closed else Color("f7cd46")
	var c_beak := Color("f7713d")
	var BIRD_R := 12.0

	# Cuerpo
	c.draw_circle(Vector2.ZERO, BIRD_R, c_body)
	c.draw_arc(Vector2.ZERO, BIRD_R, 0, TAU, 32, Color.BLACK, 2.0)
	
	# Ala
	var wing_y = -2.0 if _is_closed else 2.0
	c.draw_circle(Vector2(-4, wing_y), 6.0, c_wing)
	c.draw_arc(Vector2(-4, wing_y), 6.0, 0, TAU, 16, Color.BLACK, 2.0)

	# Ojo
	c.draw_circle(Vector2(5, -4), 5.0, Color.WHITE)
	c.draw_arc(Vector2(5, -4), 5.0, 0, TAU, 16, Color.BLACK, 2.0)
	c.draw_circle(Vector2(7, -4), 2.0, Color.BLACK)

	# Pico
	var beak = PackedVector2Array([
		Vector2(10, 0), Vector2(18, 4), Vector2(10, 8), Vector2(6, 4)
	])
	c.draw_colored_polygon(beak, c_beak)
	c.draw_polyline(beak, Color.BLACK, 2.0, true)

	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
