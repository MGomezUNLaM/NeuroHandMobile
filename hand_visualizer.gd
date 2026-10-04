extends SubViewportContainer
class_name HandVisualizer

## Visualizador interactivo 3D de mano con animación y flexión de dedos en tiempo real.
## Reemplaza imágenes estáticas por cinemática esquelética 3D real:
## - Mueve y flexiona individualmente cada dedo (pulgar, índice, medio, anular, meñique).
## - Muestra animación demostrativa del gesto y responde a datos reales del sensor BLE.
## - Permite rotación táctil/mouse interactiva en 3D para examinar la mano desde cualquier ángulo.

@export var active_finger: String = "pulgar" : set = set_active_finger
@export var is_open: bool = true : set = set_is_open
@export var flex_progress: float = 0.0 : set = set_flex_progress ## 0.0 a 1.0
@export var completed_fingers: Array = [] : set = set_completed_fingers

# Quaterniones de rotación para cada hueso: 0.0 = extendido (open), 1.0 = flexionado hacia la palma (closed)
const FINGER_BONES := {
	"pulgar": [
		{"bone": "Thumb_Metacarpal_R", "open": Quaternion(0.319933, 0.082460, 0.055315, 0.942223), "closed": Quaternion(0.329559, -0.254928, 0.152025, 0.896265)},
		{"bone": "Thumb_Proximal_R", "open": Quaternion(-0.045950, 0.027136, 0.075257, 0.995735), "closed": Quaternion(-0.303610, -0.062464, 0.228709, 0.922828)},
		{"bone": "Thumb_Distal_R", "open": Quaternion(0.055641, -0.010326, -0.013985, 0.998300), "closed": Quaternion(-0.421075, 0.118121, 0.243319, 0.865759)},
	],
	"indice": [
		{"bone": "Index_Metacarpal_R", "open": Quaternion(-0.000589, -0.000021, -0.025220, 0.999682), "closed": Quaternion(-0.001285, 0.011608, 0.016826, 0.999790)},
		{"bone": "Index_Proximal_R", "open": Quaternion(0.179788, -0.005430, -0.117482, 0.976650), "closed": Quaternion(0.024201, 0.046171, 0.651623, 0.756750)},
		{"bone": "Index_Intermediate_R", "open": Quaternion(-0.013683, 0.024668, 0.235071, 0.971569), "closed": Quaternion(-0.002395, 0.020050, 0.657488, 0.753195)},
		{"bone": "Index_Distal_R", "open": Quaternion(0.014226, 0.011991, 0.134541, 0.990733), "closed": Quaternion(-0.036982, -0.034581, 0.793887, 0.605953)},
	],
	"medio": [
		{"bone": "Middle_Metacarpal_R", "open": Quaternion(-0.035855, -0.000042, -0.049978, 0.998107), "closed": Quaternion(-0.035754, 0.000400, -0.006368, 0.999340)},
		{"bone": "Middle_Proximal_R", "open": Quaternion(-0.011947, -0.000967, 0.010501, 0.999873), "closed": Quaternion(0.044671, 0.011273, 0.686928, 0.725263)},
		{"bone": "Middle_Intermediate_R", "open": Quaternion(0.039455, -0.004929, 0.137827, 0.989658), "closed": Quaternion(0.028720, 0.018174, 0.648451, 0.760497)},
		{"bone": "Middle_Distal_R", "open": Quaternion(-0.013932, 0.000142, 0.168612, 0.985584), "closed": Quaternion(-0.013303, 0.031132, 0.815733, 0.577437)},
	],
	"anular": [
		{"bone": "Ring_Metacarpal_R", "open": Quaternion(-0.071195, -0.000016, -0.018086, 0.997298), "closed": Quaternion(-0.070266, -0.010191, 0.024331, 0.997180)},
		{"bone": "Ring_Proximal_R", "open": Quaternion(-0.120537, 0.004934, -0.041562, 0.991826), "closed": Quaternion(0.082144, 0.004790, 0.610545, 0.787696)},
		{"bone": "Ring_Intermediate_R", "open": Quaternion(0.017326, -0.018608, 0.160829, 0.986655), "closed": Quaternion(0.056462, 0.046941, 0.622987, 0.778779)},
		{"bone": "Ring_Distal_R", "open": Quaternion(-0.011352, -0.012621, 0.131984, 0.991107), "closed": Quaternion(0.081240, 0.022469, 0.834617, 0.544343)},
	],
	"menique": [
		{"bone": "Little_Metacarpal_R", "open": Quaternion(-0.091770, -0.000025, -0.028448, 0.995374), "closed": Quaternion(-0.091737, -0.020303, 0.010183, 0.995524)},
		{"bone": "Little_Proximal_R", "open": Quaternion(-0.227030, -0.004075, 0.006233, 0.973859), "closed": Quaternion(0.103134, 0.027252, 0.608737, 0.786168)},
		{"bone": "Little_Intermediate_R", "open": Quaternion(0.044926, -0.032808, 0.185059, 0.981152), "closed": Quaternion(0.098543, 0.051523, 0.656270, 0.746287)},
		{"bone": "Little_Distal_R", "open": Quaternion(-0.018055, -0.011455, 0.107075, 0.994021), "closed": Quaternion(0.126804, 0.053291, 0.791773, 0.595128)},
	],
}

const TIP_BONES := {
	"pulgar": "Thumb_Tip_R",
	"indice": "Index_Tip_R",
	"medio": "Middle_Tip_R",
	"anular": "Ring_Tip_R",
	"menique": "Little_Tip_R"
}

# Nodos 3D
var _vp: SubViewport
var _pivot: Node3D
var _hand_node: Node3D
var _skel: Skeleton3D
var _camera: Camera3D
var _marker_nodes := {}

# Estado de animación y cinemática
var _current_flex := {
	"pulgar": 0.0,
	"indice": 0.0,
	"medio": 0.0,
	"anular": 0.0,
	"menique": 0.0
}
var _anim_time: float = 0.0

# Rotación orbital interactiva (vista frontal dorsal de los nudillos)
const DEFAULT_ROTATION := Vector3(90.0, -90.0, 0.0)
var _target_hand_rot := DEFAULT_ROTATION
var _current_hand_rot := DEFAULT_ROTATION
var _is_dragging := false
var _drag_idle_timer := 0.0

# UI Overlay
var _hint_label: Label


func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_STOP
	_setup_3d_viewport()
	_setup_markers()
	_setup_glove_details()
	_setup_hint_ui()
	_apply_bone_rotations()


func _setup_3d_viewport() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	# Iluminación de estudio médico con tone mapping ACES
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.45, 0.52, 1.0)
	env.ambient_light_energy = 0.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env.environment = env
	_vp.add_child(world_env)

	# Luz principal suave (Key light)
	var light = DirectionalLight3D.new()
	light.position = Vector3(1.5, 3.0, 2.0)
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_color = Color(1.0, 0.98, 0.95, 1.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	_vp.add_child(light)

	# Luz de relleno fría (Fill light)
	var fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(15, -60, 0)
	fill_light.light_color = Color(0.55, 0.75, 0.90, 1.0)
	fill_light.light_energy = 0.55
	_vp.add_child(fill_light)

	# Luz de contorno / silueta cian Kinesis (Rim light)
	var rim_light = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(40, 150, 0)
	rim_light.light_color = Color(0.20, 0.70, 0.85, 1.0)
	rim_light.light_energy = 0.85
	_vp.add_child(rim_light)

	# Cámara perfectamente encuadrada de frente a los nudillos y dedos
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.006, 0.365)
	_camera.rotation_degrees = Vector3.ZERO
	_camera.fov = 33.0
	_vp.add_child(_camera)

	# Pivot centrado para rotación interactiva en el baricentro de la mano
	_pivot = Node3D.new()
	_pivot.rotation_degrees = _current_hand_rot
	_vp.add_child(_pivot)

	# Modelo 3D de mano - centrado geométrico exacto de la malla
	var hand_path := "res://addons/godot-xr-tools/hands/model/hand_r.gltf"
	if ResourceLoader.exists(hand_path):
		var hand_scene = load(hand_path)
		if hand_scene:
			_hand_node = hand_scene.instantiate()
			# Offset compensatorio exacto para que la palma quede perfectamente centrada y despegada del texto inferior
			_hand_node.position = Vector3(0.003, 0.006, 0.080)
			_pivot.add_child(_hand_node)



	if _hand_node:
		_skel = _hand_node.find_child("Skeleton3D", true, false)
		
		# Tela técnica lisa (sin pintar sobre UV: el UV del modelo está fragmentado y estira cualquier diseño).
		# Los detalles (placa con logo, sensores) se agregan como piezas 3D en _setup_glove_details().
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.14, 0.20, 1.0)
		var normal_tex = _load_tex("res://addons/godot-xr-tools/hands/textures/glove_normal.png")
		if normal_tex:
			mat.normal_enabled = true
			mat.normal_texture = normal_tex
			mat.normal_scale = 0.6
		mat.roughness = 0.78
		mat.metallic = 0.0
		mat.rim_enabled = true
		mat.rim = 0.35
		mat.rim_tint = 0.6
		
		for child in _hand_node.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			mi.set_surface_override_material(0, mat)


func _setup_markers() -> void:
	if _skel == null:
		return

	var finger_radii := {
		"pulgar": Vector2(0.009, 0.0135),
		"indice": Vector2(0.0075, 0.0115),
		"medio": Vector2(0.0075, 0.0115),
		"anular": Vector2(0.0070, 0.0110),
		"menique": Vector2(0.0060, 0.0100)
	}
	
	for f_key in TIP_BONES.keys():
		var bone_name: String = TIP_BONES[f_key]
		var b_idx := _skel.find_bone(bone_name)
		if b_idx == -1:
			continue
		
		var attach := BoneAttachment3D.new()
		attach.bone_name = bone_name
		_skel.add_child(attach)
		
		var marker := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var r: Vector2 = finger_radii.get(f_key, Vector2(0.0075, 0.0115))
		torus.inner_radius = r.x
		torus.outer_radius = r.y
		torus.rings = 32
		torus.ring_segments = 12
		marker.mesh = torus
		marker.position = Vector3(0.0, -0.003, 0.0)
		marker.rotation_degrees = Vector3.ZERO
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 10
		mat.albedo_color = Color(0.05, 0.82, 0.95, 0.95)
		marker.material_override = mat
		
		attach.add_child(marker)
		_marker_nodes[f_key] = {"attach": attach, "marker": marker, "mat": mat}


func _setup_hint_ui() -> void:
	_hint_label = Label.new()
	_hint_label.text = "Deslizá para rotar la vista 3D"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.35, 0.50, 0.58, 0.85))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -24
	_hint_label.offset_bottom = -4
	_hint_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_hint_label)



func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			if _is_dragging:
				_drag_idle_timer = 0.0
				if _hint_label:
					_hint_label.visible = false
	elif event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.relative
		_target_hand_rot.y += delta.x * 0.7
		_target_hand_rot.x = clampf(_target_hand_rot.x - delta.y * 0.7, 35.0, 125.0)
		_drag_idle_timer = 0.0
	elif event is InputEventScreenTouch:
		_is_dragging = event.pressed
		if _is_dragging:
			_drag_idle_timer = 0.0
			if _hint_label:
				_hint_label.visible = false
	elif event is InputEventScreenDrag and _is_dragging:
		var delta: Vector2 = event.relative
		_target_hand_rot.y += delta.x * 0.7
		_target_hand_rot.x = clampf(_target_hand_rot.x - delta.y * 0.7, 35.0, 125.0)
		_drag_idle_timer = 0.0


func set_active_finger(value: String) -> void:
	active_finger = value.to_lower().strip_edges()


func set_is_open(value: bool) -> void:
	is_open = value


func set_flex_progress(value: float) -> void:
	flex_progress = clampf(value, 0.0, 1.0)


func set_completed_fingers(value: Array) -> void:
	completed_fingers = value


func _process(delta: float) -> void:
	_anim_time += delta

	# Rotación interactiva suave y auto-retorno tras inactividad
	if not _is_dragging:
		_drag_idle_timer += delta
		if _drag_idle_timer > 3.5:
			_target_hand_rot = _target_hand_rot.lerp(DEFAULT_ROTATION, delta * 1.5)

	if _pivot:
		_current_hand_rot = _current_hand_rot.lerp(_target_hand_rot, delta * 9.0)
		_pivot.rotation_degrees = _current_hand_rot

	# Cálculo de la flexión de cada dedo
	for f_key in FINGER_BONES.keys():
		var target_flex := 0.0
		
		if f_key == active_finger:
			if is_open:
				# Gesto de reposo: permanece extendido (o sigue lectura si el usuario flexiona)
				target_flex = flex_progress if flex_progress > 0.1 else 0.0
			else:
				# Gesto de cierre:
				if flex_progress > 0.05:
					# Sigue el sensor del guante en tiempo real
					target_flex = flex_progress
				else:
					# Animación demostrativa que muestra cómo doblar el dedo hacia la palma
					var wave := (sin(_anim_time * 3.2) + 1.0) * 0.5
					target_flex = ease(wave, 0.8)
		else:
			# Otros dedos descansan extendidos
			target_flex = 0.0

		_current_flex[f_key] = lerpf(_current_flex[f_key], target_flex, clampf(delta * 12.0, 0.0, 1.0))

	# Aplicar cinemática esquelética a los huesos 3D
	_apply_bone_rotations()
	_update_markers()


func _apply_bone_rotations() -> void:
	if _skel == null:
		return

	for f_key in FINGER_BONES.keys():
		var flex: float = _current_flex[f_key]
		for b_data in FINGER_BONES[f_key]:
			var b_idx: int = _skel.find_bone(b_data["bone"])
			if b_idx != -1:
				var open_q: Quaternion = b_data["open"]
				var closed_q: Quaternion = b_data["closed"]
				var current_q := open_q.slerp(closed_q, flex)
				_skel.set_bone_pose_rotation(b_idx, current_q)


func _update_markers() -> void:
	var pulse := (sin(_anim_time * 5.0) + 1.0) * 0.5

	for f_key in _marker_nodes.keys():
		var data = _marker_nodes[f_key]
		var marker: MeshInstance3D = data["marker"]
		var mat: StandardMaterial3D = data["mat"]

		if f_key == active_finger:
			marker.visible = true
			# Pulso cian brillante sobre el dedo activo
			mat.albedo_color = Color(0.12, 0.70 + pulse * 0.25, 0.85, 0.95)
			var scale_factor := 1.0 + pulse * 0.25
			marker.scale = Vector3(scale_factor, scale_factor, scale_factor)
		elif completed_fingers.has(f_key):
			marker.visible = true
			# Verde esmeralda para dedos completados
			mat.albedo_color = Color(0.15, 0.75, 0.40, 0.85)
			marker.scale = Vector3(0.85, 0.85, 0.85)
		else:
			# Inactivo sutil
			marker.visible = false


func _setup_glove_details() -> void:
	if _hand_node == null or _skel == null:
		return

	# Ejes del modelo (espacio local de la mano): +X = dorso, -Z = hacia los dedos, +Y = lado pulgar
	const DORSAL := Vector3(1, 0, 0)
	var hub_center := Vector3(0.027, 0.0, -0.034)

	var cyan_mat := StandardMaterial3D.new()
	cyan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyan_mat.albedo_color = Color(0.0, 0.85, 1.0)

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.06, 0.09, 0.13)
	plate_mat.roughness = 0.35
	plate_mat.metallic = 0.4

	var plate_basis := Basis(Vector3(0, 0, -1), DORSAL, Vector3(0, -1, 0))

	# Borde cian de la placa hexagonal
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.0205
	rim_mesh.bottom_radius = 0.0205
	rim_mesh.height = 0.003
	rim_mesh.radial_segments = 6
	rim.mesh = rim_mesh
	rim.material_override = cyan_mat
	rim.transform = Transform3D(plate_basis, hub_center)
	_hand_node.add_child(rim)

	# Placa oscura (sobresale un poco para que el cian quede como contorno)
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.018
	plate_mesh.bottom_radius = 0.0185
	plate_mesh.height = 0.0045
	plate_mesh.radial_segments = 6
	plate.mesh = plate_mesh
	plate.material_override = plate_mat
	plate.transform = Transform3D(plate_basis, hub_center)
	_hand_node.add_child(plate)

	# Emblema "K" de Kinesis sobre la placa (Label3D = vectorial, nítido a cualquier tamaño),
	# mirando hacia afuera del dorso y "derecho" hacia los dedos
	var emblem := Label3D.new()
	emblem.text = "K"
	emblem.font_size = 96
	emblem.pixel_size = 0.00019
	emblem.outline_size = 0
	emblem.modulate = Color(0.0, 0.9, 1.0)
	emblem.shaded = false
	emblem.double_sided = false
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var emblem_font := SystemFont.new()
	emblem_font.font_names = PackedStringArray(["Montserrat", "Segoe UI", "Roboto", "Arial"])
	emblem_font.font_weight = 800
	emblem.font = emblem_font
	var emblem_basis := Basis(Vector3(0, -1, 0), Vector3(0, 0, -1), DORSAL)
	emblem.transform = Transform3D(emblem_basis, hub_center + DORSAL * 0.0026)
	_hand_node.add_child(emblem)

	# Sensores en los nudillos + pistas hacia la placa.
	# Los metacarpianos no se mueven al flexionar, así que estas piezas pueden ser estáticas.
	var skel_to_hand: Transform3D = _hand_node.global_transform.affine_inverse() * _skel.global_transform
	for bone_name in ["Index_Proximal_R", "Middle_Proximal_R", "Ring_Proximal_R", "Little_Proximal_R"]:
		var idx := _skel.find_bone(bone_name)
		if idx == -1:
			continue
		var joint: Vector3 = skel_to_hand * _skel.get_bone_global_rest(idx).origin
		var pod_pos := joint + DORSAL * 0.0095

		var pod := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.0042
		sphere.height = 0.0084
		pod.mesh = sphere
		pod.material_override = cyan_mat
		pod.position = pod_pos
		_hand_node.add_child(pod)

		var start := hub_center + DORSAL * 0.001 + (pod_pos - hub_center).normalized() * 0.019
		_hand_node.add_child(_make_bar(start, pod_pos, 0.0011, cyan_mat))


func _make_bar(a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 8
	bar.mesh = cyl
	bar.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3(1, 0, 0)).normalized()
	var z := x.cross(y)
	bar.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return bar


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_path) or FileAccess.file_exists(path):
		var img := Image.load_from_file(global_path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null
