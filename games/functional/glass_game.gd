extends Control

signal score_updated(score: int)

@onready var _glass: Node3D = $Glass
@onready var _target: MeshInstance3D = $Target

var _is_running := false
var _is_thrusting := false
var _score := 0

const START_X := -4.0
const TARGET_X := 4.0
const MOVE_SPEED := 2.5 # Unidades 3D por segundo
var _reset_cooldown := 0.0

var _target_material: StandardMaterial3D

var _time_passed := 0.0

func _ready() -> void:
	# Forzar modo horizontal en móviles para este minijuego
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
		
	_glass.position.x = START_X
	
	# Rotar la botella para que se vea más de costado
	var glass_model = _glass.get_node_or_null("GlassModel")
	if glass_model:
		glass_model.rotation_degrees.y = -90.0
		glass_model.rotation_degrees.z = -15.0 # Enderezar un poco si estaba muy inclinada
		_fix_transparency_depth(glass_model)

	# Asegurar material único para tweening del target
	if _target.mesh != null and _target.mesh.material != null:
		_target_material = _target.mesh.material.duplicate() as StandardMaterial3D
		_target.set_surface_override_material(0, _target_material)

func _fix_transparency_depth(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 0):
			var mat = mesh_inst.get_active_material(i)
			if mat is BaseMaterial3D:
				# Si el material es transparente, forzamos que escriba en el depth buffer
				# para evitar que el Depth of Field lo atraviese y lo desenfoque
				if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
					
					# Aumentar drásticamente la opacidad para que la botella se vea más sólida
					var color = mat.albedo_color
					color.a = maxf(color.a, 0.90) # Asegurar al menos 90% de opacidad
					mat.albedo_color = color
					
					# Darle un toque de reflejo tipo vidrio sólido
					mat.roughness = 0.1
					
	for child in node.get_children():
		_fix_transparency_depth(child)

func _exit_tree() -> void:
	# Restaurar modo vertical al salir del minijuego
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

func start_game() -> void:
	_is_running = true
	_is_thrusting = false
	_score = 0
	_reset_cooldown = 0.0
	_glass.position.x = START_X
	score_updated.emit(_score)

func trigger_action() -> void:
	pass

func set_thrust(thrust: bool) -> void:
	_is_thrusting = thrust

func set_flex(flex_value: float) -> void:
	pass

func _process(delta: float) -> void:
	_time_passed += delta
	
	# Animación de levitación y rotación sutil para el Target
	if is_instance_valid(_target):
		_target.rotation.y += delta * 1.5
		_target.position.y = 0.05 + sin(_time_passed * 3.0) * 0.02

	if not _is_running:
		return

	if _reset_cooldown > 0.0:
		_reset_cooldown -= delta
		if _reset_cooldown <= 0.0:
			_glass.position.x = START_X
			if _target_material != null:
				_target_material.emission_energy_multiplier = 4.0
		return

	if _is_thrusting:
		# Mover en el eje X (3D)
		_glass.position.x += MOVE_SPEED * delta
		
		# Si alcanza el objetivo (esperamos un poco más para que la botella entre más al aro)
		if _glass.position.x >= TARGET_X - 0.5:
			_glass.position.x = TARGET_X - 0.5
			_score += 1
			score_updated.emit(_score)
			_reset_cooldown = 1.0
			
			# Destello neón
			if _target_material != null:
				var tween = create_tween()
				tween.tween_property(_target_material, "emission_energy_multiplier", 15.0, 0.2)
				tween.tween_property(_target_material, "emission_energy_multiplier", 4.0, 0.8)
