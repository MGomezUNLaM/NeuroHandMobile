extends Node3D

signal game_over
signal score_updated(new_score: int)

enum State { IDLE, GRABBED, AIMING, THROWN }

var _state := State.IDLE
var _score := 0
var _time_left := 30.0

@onready var _ball := $Ball as RigidBody3D
@onready var _state_label := $UI/StateLabel as Label
@onready var _score_label := $UI/ScoreLabel as Label
@onready var _timer_label := $UI/TimerLabel as Label
@onready var _time_label_3d := $ArcadeModel/TimeLabel3D as Label3D
@onready var _score_label_3d := $ArcadeModel/ScoreLabel3D as Label3D

# Umbrales
const FLEX_GRAB_THRESHOLD := 60.0
const FLEX_RELEASE_THRESHOLD := 30.0
const PITCH_AIM_THRESHOLD := 40.0

var _initial_ball_transform: Transform3D
var _net_material: ShaderMaterial = null

func _ready() -> void:
	# Iluminación ambiental y fondo oscuro para evitar el gris de Godot
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05) # Oscuro
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 1.0)
	env.ambient_light_energy = 1.0
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	# Configurar fondo como Sprite3D gigante para tapar todo
	var bg_sprite = Sprite3D.new()
	bg_sprite.texture = load("res://assets/basket/arcade_real_bg.jpg")
	bg_sprite.pixel_size = 0.15 # Mucho más grande
	bg_sprite.position = Vector3(0, 5, -40) # Bien al fondo
	add_child(bg_sprite)
	
	# Mover la pelota más arriba y cerca de la cámara para que no quede dentro de la máquina
	_ball.transform.origin = Vector3(0, 0.0, 3.0)
	_initial_ball_transform = _ball.transform
	_reset_ball()
	
	# Ocultar mallas de prueba (el modelo visual ahora está instanciado en el .tscn directamente)
	if has_node("Board/MeshInstance3D"):
		$Board/MeshInstance3D.hide()
	if has_node("Hoop/MeshInstance3D"):
		$Hoop/MeshInstance3D.hide() 
		
	# Inyectar shader de red en el modelo
	if has_node("ArcadeModel"):
		_inject_net_shader($ArcadeModel)
		
	# --- GENERAR ARO HUECO PARA QUE LA PELOTA PASE ---
	if has_node("Hoop/CollisionShape3D"):
		$Hoop/CollisionShape3D.queue_free() # Borramos el cilindro sólido
		
	var hoop_radius = 0.45
	var segments = 12
	for i in range(segments):
		var angle = i * (PI * 2.0 / segments)
		var box_col = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(0.08, 0.08, hoop_radius * 0.55)
		box_col.shape = box_shape
		box_col.position = Vector3(cos(angle) * hoop_radius, 0, sin(angle) * hoop_radius)
		box_col.rotation.y = -angle
		$Hoop.add_child(box_col)
		
	# Ajustar el área de score para que solo detecte cuando cae por el medio
	if has_node("Hoop/ScoreArea/CollisionShape3D"):
		var score_col = $Hoop/ScoreArea/CollisionShape3D
		var new_shape = CylinderShape3D.new()
		new_shape.radius = 0.25 # Más chico que el aro
		new_shape.height = 0.2
		score_col.shape = new_shape
		$Hoop/ScoreArea.position.y = -0.4 # Más abajo para confirmar que pasó
	# ----------------------------------------------------
	
	if BleManager.state == BleManager.State.CONNECTED:
		BleManager.flex_updated.connect(_on_flex_updated)
		BleManager.imu_updated.connect(_on_imu_updated)

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0:
		_time_left = 0
		_timer_label.text = "0"
		if _time_label_3d:
			_time_label_3d.text = "000"
		game_over.emit()
		return
		
	_timer_label.text = str(int(ceil(_time_left)))
	if _time_label_3d:
		_time_label_3d.text = "%03d" % int(ceil(_time_left))
		
	# Actualizar posición de la pelota en el shader de la red
	if _net_material != null and _ball != null:
		_net_material.set_shader_parameter("ball_pos", _ball.global_position)

func _inject_net_shader(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh = node.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var mat = node.get_surface_override_material(i)
				if mat == null:
					mat = mesh.surface_get_material(i)
					
				if mat is StandardMaterial3D:
					# Si tiene alpha scissor o alguna transparencia, asumimos que es la red
					if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						var shader_mat = ShaderMaterial.new()
						shader_mat.shader = preload("res://games/basket/net_shader.gdshader")
						shader_mat.set_shader_parameter("albedo_tex", mat.albedo_texture)
						node.set_surface_override_material(i, shader_mat)
						_net_material = shader_mat
						
	for child in node.get_children():
		_inject_net_shader(child)

func _on_flex_updated(flex: float) -> void:
	if _state == State.IDLE and flex >= FLEX_GRAB_THRESHOLD:
		_change_state(State.GRABBED)
	elif _state == State.AIMING and flex <= FLEX_RELEASE_THRESHOLD:
		_throw_ball()

func _on_imu_updated(pitch: float, roll: float, yaw: float) -> void:
	if _state == State.GRABBED and pitch >= PITCH_AIM_THRESHOLD:
		_change_state(State.AIMING)

func _change_state(new_state: State) -> void:
	_state = new_state
	match _state:
		State.IDLE:
			_state_label.text = "Agarra la pelota (Flexiona)"
			_state_label.modulate = Color.WHITE
		State.GRABBED:
			_state_label.text = "¡Levanta la mano para apuntar!"
			_state_label.modulate = Color.YELLOW
			# Acercar la pelota al jugador simulando que la agarra
			var tw = create_tween()
			tw.tween_property(_ball, "position", Vector3(0, 1.5, 4.0), 0.2)
		State.AIMING:
			_state_label.text = "¡Apunta y SUELTA los dedos!"
			_state_label.modulate = Color.GREEN
		State.THROWN:
			_state_label.text = "¡Tiro!"
			_state_label.modulate = Color.ORANGE

func _throw_ball() -> void:
	_change_state(State.THROWN)
	_ball.freeze = true # Mantenemos congelado para ignorar la física durante el vuelo
	
	var target_pos = $Hoop/ScoreArea.global_position
	var start_pos = _ball.global_position
	var flight_time = 0.9 # Tiempo de vuelo para que sea suave y no se achique tan brusco
	var peak_y = max(start_pos.y, target_pos.y) + 2.5 # Altura máxima de la parábola
	
	# Tween para movimiento horizontal (X y Z) directo al aro
	var tw_xz = create_tween()
	tw_xz.set_parallel(true)
	tw_xz.tween_property(_ball, "global_position:x", target_pos.x, flight_time)
	tw_xz.tween_property(_ball, "global_position:z", target_pos.z, flight_time)
	
	# Engaño visual: agrandamos el modelo de la pelota mientras vuela para
	# contrarrestar el encogimiento de la perspectiva 3D y que no se vea minúscula.
	if has_node("Ball/BallModel"):
		var tw_scale = create_tween()
		tw_scale.tween_property($Ball/BallModel, "scale", Vector3(9, 9, 9), flight_time)
	
	# Tween para el arco vertical (sube y luego baja)
	var tw_y = create_tween()
	tw_y.tween_property(_ball, "global_position:y", peak_y, flight_time / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_y.tween_property(_ball, "global_position:y", target_pos.y, flight_time / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Al llegar al aro, habilitamos gravedad para que caiga por la red naturalmente
	tw_y.tween_callback(func():
		_ball.freeze = false
		_ball.linear_velocity = Vector3(0, -2, 0) # Empujón leve hacia abajo
	)
	
	# Reiniciar después de que cae
	get_tree().create_timer(flight_time + 1.5).timeout.connect(_reset_ball)

func _reset_ball() -> void:
	_ball.freeze = true
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.transform = _initial_ball_transform
	
	# Restaurar el tamaño original de la pelota
	if has_node("Ball/BallModel"):
		$Ball/BallModel.scale = Vector3(5, 5, 5)
	_change_state(State.IDLE)

func _on_score_area_body_entered(body: Node3D) -> void:
	if body == _ball and _state == State.THROWN:
		_score += 10
		_score_label.text = str(_score)
		if _score_label_3d:
			_score_label_3d.text = "%03d" % _score
		score_updated.emit(_score)
		
		# Feedback visual de enceste
		var tw = create_tween()
		_score_label.scale = Vector2(1.5, 1.5)
		_score_label.modulate = Color.GREEN
		tw.tween_property(_score_label, "scale", Vector2.ONE, 0.3)
		tw.tween_property(_score_label, "modulate", Color.WHITE, 0.3)

func _on_back_pressed() -> void:
	game_over.emit()
