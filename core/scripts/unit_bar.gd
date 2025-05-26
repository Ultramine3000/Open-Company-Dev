# ChildRoot.gd - Simplified version without get() method issues
extends Node3D

@onready var _mesh : MeshInstance3D = $UnitIcon
@onready var health_bar : MeshInstance3D = $HealthBar

# Add squad ownership tracking
var squad_owner: Node = null
var is_being_deleted: bool = false

func _ready() -> void:
	# Automatically set the unit icon from parent's CombatUnitData
	setup_unit_icon_from_parent()
	
	# Set the squad owner to prevent cross-squad interference
	squad_owner = get_parent()

func setup_unit_icon_from_parent() -> void:
	# Get parent node and check if it has CombatUnitData
	var parent_node = get_parent()
	if parent_node == null:
		push_warning("ChildRoot has no parent node")
		return
	
	# Try to get CombatUnitData from parent
	var combat_data = null
	
	# Method 1: Check for 'stats' property (as used in your squad script)
	if "stats" in parent_node:
		combat_data = parent_node.stats
	# Method 2: If CombatUnitData is a direct property/variable
	elif "combat_unit_data" in parent_node:
		combat_data = parent_node.combat_unit_data
	# Method 3: If CombatUnitData is a child node
	elif parent_node.has_node("CombatUnitData"):
		combat_data = parent_node.get_node("CombatUnitData")
	# Method 4: If parent has a getter method
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
	# Don't update if being deleted
	if is_being_deleted:
		return
		
	# Verify this request is coming from the correct squad owner
	if squad_owner and is_instance_valid(squad_owner):
		# Check if squad owner is dead using direct property access
		if "is_dead" in squad_owner and squad_owner.is_dead:
			return  # Don't update health bar for dead squads
	
	# Ensure health bar mesh is unique 
	var new_mesh := health_bar.mesh.duplicate()
	# Adjust bar width (range 0-1)
	new_mesh.size.x = health_percent
	# Ensure bar is always left justified
	new_mesh.center_offset.x = (-1+health_percent)/2
	health_bar.mesh = new_mesh

func delete_unit_bar() -> void:
	# Prevent multiple deletion calls
	if is_being_deleted:
		return
		
	# Verify this deletion request is coming from the correct squad owner
	if squad_owner and is_instance_valid(squad_owner):
		# Only delete if the squad owner is actually dead
		var owner_is_dead = false
		
		if squad_owner.has_method("is_squad_dead"):
			owner_is_dead = squad_owner.is_squad_dead()
		elif "is_dead" in squad_owner:
			owner_is_dead = squad_owner.is_dead
		
		if not owner_is_dead:
			push_warning("delete_unit_bar called but squad owner is not dead!")
			return
	
	# Mark as being deleted to prevent further operations
	is_being_deleted = true
	
	# Properly remove the unit bar
	visible = false
	
	# Disable processing to prevent any further operations
	set_process(false)
	set_physics_process(false)

# Simple ownership verification
func is_owned_by(node: Node) -> bool:
	return squad_owner == node and is_instance_valid(node)
