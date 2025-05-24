# ChildRoot.gd
extends Node3D
@onready var _mesh : MeshInstance3D = $UnitIcon
@onready var health_bar : MeshInstance3D = $HealthBar

func _ready() -> void:
	# Automatically set the unit icon from parent's CombatUnitData
	setup_unit_icon_from_parent()

func setup_unit_icon_from_parent() -> void:
	# Get parent node and check if it has CombatUnitData
	var parent_node = get_parent()
	if parent_node == null:
		push_warning("ChildRoot has no parent node")
		return
	
	# Try to get CombatUnitData from parent
	var combat_data = null
	
	# Method 1: If CombatUnitData is a direct property/variable
	if "combat_unit_data" in parent_node:
		combat_data = parent_node.combat_unit_data
	# Method 2: If CombatUnitData is a child node
	elif parent_node.has_node("CombatUnitData"):
		combat_data = parent_node.get_node("CombatUnitData")
	# Method 3: If parent has a getter method
	elif parent_node.has_method("get_combat_unit_data"):
		combat_data = parent_node.get_combat_unit_data()
	
	if combat_data == null:
		push_warning("Parent node does not have CombatUnitData")
		return
	
	# Get the unit icon texture from CombatUnitData
	var unit_icon_texture = null
	if "unit_icon" in combat_data:
		unit_icon_texture = combat_data.unit_icon
	elif combat_data.has_method("get_unit_icon"):
		unit_icon_texture = combat_data.get_unit_icon()
	
	if unit_icon_texture != null:
		set_albedo_texture(unit_icon_texture)
	else:
		push_warning("CombatUnitData does not have unit_icon property")

func set_albedo_texture(tex : Texture2D) -> void:
	if !_mesh:
		return      # safety guard
	
	# If an override material is set already, don't change it
	var mat : Material = _mesh.get_surface_override_material(0)
	# If there is no override, fall back to the active surface material
	if mat == null:
		mat = _mesh.get_active_material(0)            # might still be null
		# Ensure material is unique 
		if mat:
			mat = mat.duplicate()
		else:
			mat = StandardMaterial3D.new()
		
		# Sets the override material 
		_mesh.set_surface_override_material(0, mat)
	
	# ensures std_mat is a StandardMaterial3D
	var std_mat := mat as StandardMaterial3D
	if std_mat == null:
		push_warning(
			"Material on %s is not a StandardMaterial3D – albedo texture not applied."
			% _mesh.name
		)
		return
	
	# Set albedo texture and transparency properties
	std_mat.albedo_texture = tex
	std_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	std_mat.resource_local_to_scene = true    # keeps the copy local to this scene
	
	# Enable transparency
	std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std_mat.flags_transparent = true
	std_mat.albedo_color.a = 1.0  # You can adjust this value (0.0-1.0) for overall transparency
	
func set_health_bar(health_percent : float) -> void:
	# Ensure health bar mesh is unique 
	var new_mesh := health_bar.mesh.duplicate()
	# Adjust bar width (range 0-1)
	new_mesh.size.x = health_percent
	# Ensure bar is always left justified
	new_mesh.center_offset.x = (-1+health_percent)/2
	health_bar.mesh = new_mesh
	
func delete_unit_bar() -> void:
	# delete entire unit icon (for when unit dies)
	visible = false
