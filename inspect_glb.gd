extends SceneTree
func _init():
	var packed = load('res://assets/basket/arcade_basketball_machine__prop.glb')
	var instance = packed.instantiate()
	_print_mesh_info(instance, '')
	quit()

func _print_mesh_info(node, indent):
	if node is MeshInstance3D:
		print(indent + 'Mesh: ' + node.name)
		var mesh = node.mesh
		for i in range(mesh.get_surface_count()):
			var mat = mesh.surface_get_material(i)
			var mat_name = mat.resource_name if mat else 'None'
			print(indent + '  Surface ' + str(i) + ': ' + mat_name)
	for child in node.get_children():
		_print_mesh_info(child, indent + '  ')
