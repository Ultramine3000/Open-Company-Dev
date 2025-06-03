extends Node3D
class_name ProjectileDamage

@export var damage_amount: int = 1
@export var check_interval: float = 0.02
@export var impact_effect_scene: PackedScene

@onready var raycast: RayCast3D = get_child(0)

var check_timer: float = 0.0
var target_info: Dictionary = {}  # Store target info from muzzle flash

func _ready():
	if not raycast or not raycast is RayCast3D:
		raycast = get_node_or_null("RayCast3D")
		if not raycast:
			push_error("ProjectileDamage: No RayCast3D child found!")
			return
	
	raycast.enabled = true

# NEW: Method to receive target info from muzzle flash
func set_target_info(target_node: Node, target_pos: Vector3, distance: float):
	target_info = {
		"target_node": target_node,
		"target_position": target_pos,
		"distance": distance
	}

func _physics_process(delta: float):
	if not raycast or not raycast.enabled:
		return
	
	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		_check_for_collision()

func _check_for_collision():
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var collision_point = raycast.get_collision_point()
		var collision_normal = raycast.get_collision_normal()
		
		print("Raycast hit: ", collider.name, " (Type: ", collider.get_class(), ")")
		
		if collider and _is_infantry_target(collider):
			_deal_damage_to_target(collider)
			_spawn_impact_effect(collision_point, collision_normal)
			_destroy_tracer()

func _is_infantry_target(target: Node) -> bool:
	print("Checking target: ", target.name, " for infantry validity")
	
	# SIMPLIFIED: Check if target has take_damage method OR is a squad clone
	if target.has_method("take_damage"):
		print("Target has take_damage method: ", target.name)
		return true
	
	# Check if target is in squad_clones group (our simplified clone system)
	if target.is_in_group("squad_clones"):
		print("Target is a squad clone: ", target.name)
		return true
	
	# Check if we can find a related target
	var target_with_damage = _find_target_with_take_damage(target)
	if target_with_damage:
		print("Found related target: ", target_with_damage.name)
		return true
	
	print("Target is not a valid infantry target")
	return false

func _deal_damage_to_target(target: Node):
	print("Attempting to deal damage to: ", target.name, " (Type: ", target.get_class(), ")")
	
	# SIMPLIFIED APPROACH: Direct damage dealing
	
	# Case 1: Target has take_damage method (squad leaders)
	if target.has_method("take_damage"):
		print("Target has take_damage method - dealing damage directly")
		target.take_damage(damage_amount)
		_on_damage_dealt(target)
		return
	
	# Case 2: Target is a squad clone (in squad_clones group)
	if target.is_in_group("squad_clones"):
		print("Target is a squad clone - handling clone damage")
		_handle_clone_damage(target)
		return
	
	# Case 3: Try to find related target with take_damage
	var target_with_damage = _find_target_with_take_damage(target)
	if target_with_damage:
		print("Found related target with take_damage method: ", target_with_damage.name)
		if target_with_damage.has_method("take_damage"):
			target_with_damage.take_damage(damage_amount)
		else:
			_handle_clone_damage(target_with_damage)
		_on_damage_dealt(target_with_damage)
		return
	
	print("No valid target found for damage dealing")

func _handle_clone_damage(clone: Node3D):
	"""Handle damage to a clone using the simplified system"""
	print("Handling clone damage for: ", clone.name)
	
	# Get the squad reference from the clone's metadata
	var squad_unit = clone.get_meta("squad_reference", null)
	
	if not squad_unit:
		# Fallback: Try to find squad by squad_id
		var squad_id = clone.get_meta("squad_id", "")
		if squad_id != "":
			squad_unit = _find_squad_by_id(squad_id)
	
	if squad_unit and squad_unit.has_method("handle_clone_damage"):
		print("Found squad unit, delegating damage to squad")
		squad_unit.handle_clone_damage(clone, damage_amount)
		_on_damage_dealt(clone)
	else:
		print("ERROR: Could not find squad unit for clone: ", clone.name)
		# Fallback: Apply damage directly to clone metadata
		_apply_direct_clone_damage(clone)

func _apply_direct_clone_damage(clone: Node3D):
	"""Fallback method to apply damage directly to clone metadata"""
	print("Applying direct damage to clone: ", clone.name)
	
	if clone.get_meta("is_dead", false):
		return
	
	var current_health = clone.get_meta("health", 0)
	current_health = max(0, current_health - damage_amount)
	clone.set_meta("health", current_health)
	
	print("Clone health updated: ", current_health)
	
	if current_health <= 0:
		clone.set_meta("is_dead", true)
		print("Clone marked as dead")
		
		# Try to notify squad unit if possible
		var squad_unit = clone.get_meta("squad_reference", null)
		if squad_unit and squad_unit.has_method("_kill_clone_immediately"):
			squad_unit._kill_clone_immediately(clone)

func _find_squad_by_id(squad_id: String) -> Node:
	"""Find squad unit by squad_id"""
	var all_squads = get_tree().get_nodes_in_group("allies") + get_tree().get_nodes_in_group("axis")
	for squad in all_squads:
		if squad.has_method("get") and squad.get("squad_id") == squad_id:
			return squad
	return null

func _find_target_with_take_damage(target: Node) -> Node:
	"""Search for a node with take_damage method in the target's hierarchy"""
	# Check the target itself
	if target.has_method("take_damage"):
		return target
	
	# Check if target is a squad clone
	if target.is_in_group("squad_clones"):
		return target
	
	# Check parent
	var parent = target.get_parent()
	if parent and (parent.has_method("take_damage") or parent.is_in_group("squad_clones")):
		return parent
	
	# Check children
	for child in target.get_children():
		if child.has_method("take_damage") or child.is_in_group("squad_clones"):
			return child
	
	return null

func _spawn_impact_effect(position: Vector3, normal: Vector3):
	if not impact_effect_scene:
		print("No impact effect scene assigned!")
		return
	
	var impact_effect = impact_effect_scene.instantiate()
	get_tree().current_scene.add_child(impact_effect)
	impact_effect.global_position = position
	
	if impact_effect.has_method("look_at"):
		impact_effect.look_at(position + normal, Vector3.UP)
	
	print("Spawned impact effect at: ", position)

func _destroy_tracer():
	var tracer = self
	
	# Find the tracer root
	while tracer.get_parent() and not tracer.name.contains("tracer") and not tracer.name.contains("Tracer"):
		tracer = tracer.get_parent()
		if tracer == get_tree().current_scene:
			tracer = self
			break
	
	print("Destroying tracer: ", tracer.name)
	tracer.queue_free()

func _on_damage_dealt(target: Node):
	print("Damage dealt to: ", target.name)
	# Override this method or connect to signals for custom behavior

# UTILITY METHODS
func force_damage_check():
	_check_for_collision()

func set_damage_amount(amount: int):
	damage_amount = amount

func set_impact_effect(scene: PackedScene):
	impact_effect_scene = scene
