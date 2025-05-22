@tool
extends MeshInstance3D

func _process(delta: float) -> void:
	if (randf() > 0.8):
		self.visible = true
		self.rotate(Vector3.RIGHT, randf_range(0, 360))
		self.mesh.surface_get_material(0).alpha_scissor_threshold = randf_range(0.1, 1.0)
		self.mesh.surface_get_material(0).uv1_offset.y = randf_range(0.0, 1.0)
	else:
		self.visible = false

# Make sure the script animated properties are not changing everytime you save
func _notification(what:int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			self.visible = true
			self.rotation = Vector3(0, 0, deg_to_rad(90))
			self.mesh.surface_get_material(0).alpha_scissor_threshold = 0.1
			self.mesh.surface_get_material(0).uv1_offset.y = 0.0
