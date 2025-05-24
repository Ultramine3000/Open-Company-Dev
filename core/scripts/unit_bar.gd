# ChildRoot.gd
extends Node3D

@onready var _mesh : MeshInstance3D = $UnitIcon
@onready var health_bar : MeshInstance3D = $HealthBar

	
func set_albedo_texture(tex : Texture2D) -> void:
	if !_mesh:
		return      # safety guard

	# 1) Prefer the material that’s already set as a SURFACE-OVERRIDE
	var mat : Material = _mesh.get_surface_override_material(0)

	# 2) If there is no override, fall back to the active surface material
	if mat == null:
		mat = _mesh.get_active_material(0)            # might still be null

		# Make the material unique to *this* child before editing it
		if mat:
			mat = mat.duplicate()
		else:
			mat = StandardMaterial3D.new()

		_mesh.set_surface_override_material(0, mat)

	# 3) At this point we’re guaranteed the material on surface 0 is ours
	var std_mat := mat as StandardMaterial3D
	if std_mat == null:
		push_warning(
			"Material on %s is not a StandardMaterial3D – albedo texture not applied."
			% _mesh.name
		)
		return

	std_mat.albedo_texture = tex
	std_mat.resource_local_to_scene = true    # keeps the copy local to this scene
	
	
func set_health_bar(health_percent : float) -> void:
	var new_mesh := health_bar.mesh.duplicate()
	new_mesh.size.x = health_percent
	new_mesh.center_offset.x = (-1+health_percent)/2
	health_bar.mesh = new_mesh
	
func delete_unit_bar() -> void:
	visible = false
	
