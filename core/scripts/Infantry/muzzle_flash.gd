extends Node

@onready var animation_player: AnimationPlayer
@onready var emitter: GPUParticles3D
var tracer_scene: PackedScene
var tracer_speed: float = 200.0
var tracer_max_distance: float = 200.0
var muzzle_offset: Vector3 = Vector3.ZERO

# Animation control - CHANGED: Default to false so animations are managed centrally
@export_group("Animation Control")
@export var auto_trigger_fire_animation: bool = false
@export var auto_trigger_aim_animation: bool = false

# Accuracy system - Exported for tweaking
@export_group("Accuracy Settings")
@export var short_range_accuracy: float = 0.9
@export var medium_range_accuracy: float = 0.7
@export var long_range_accuracy: float = 0.4
@export var short_range_threshold: float = 10.0
@export var medium_range_threshold: float = 20.0

# Internal accuracy system variables
var target_position: Vector3 = Vector3.ZERO
var firing_distance: float = 0.0
var shooter_position: Vector3 = Vector3.ZERO
var target_node: Node = null

# NEW: Current target tracking for accuracy
var current_target: Node = null
var last_fire_time: float = 0.0

func _ready():
	animation_player = get_parent().get_node_or_null("AnimationPlayer")
	tracer_scene = preload("res://scenes/tracer.tscn")
	emitter = get_child(0)
	if emitter:
		emitter.emitting = false
	
	# Only connect animation signals if auto-triggering is enabled
	if auto_trigger_fire_animation and animation_player:
		if animation_player.has_signal("animation_started"):
			animation_player.animation_started.connect(_on_animation_started)
		else:
			animation_player.animation_changed.connect(_on_animation_changed)
	elif animation_player:
		# Connect to animation signals to sync with centralized animations
		if animation_player.has_signal("animation_started"):
			animation_player.animation_started.connect(_on_animation_started_sync)
		else:
			animation_player.animation_changed.connect(_on_animation_changed_sync)

func _on_animation_started(animation_name: String):
	"""Original method - only used if auto_trigger_fire_animation is true"""
	if animation_name == "Fire" or animation_name == "Crouch_Fire":
		await get_tree().create_timer(0.05).timeout
		if animation_player and animation_player.current_animation == animation_name:
			activate_muzzle_flash()
			spawn_visual_tracer()

func _on_animation_changed():
	"""Original method - only used if auto_trigger_fire_animation is true"""
	if not animation_player:
		return
		
	var current_anim = animation_player.current_animation
	if (current_anim == "Fire" or current_anim == "Crouch_Fire") and animation_player.is_playing() and current_anim != "Move":
		activate_muzzle_flash()
		spawn_visual_tracer()

# NEW: Sync methods for centralized animation system
func _on_animation_started_sync(animation_name: String):
	"""Sync with centralized animation system - get fresh target data"""
	if animation_name == "Fire" or animation_name == "Crouch_Fire":
		await get_tree().create_timer(0.05).timeout
		if animation_player and animation_player.current_animation == animation_name:
			_update_current_target_from_squad()
			activate_muzzle_flash()
			spawn_visual_tracer()

func _on_animation_changed_sync():
	"""Sync with centralized animation system - get fresh target data"""
	if not animation_player:
		return
		
	var current_anim = animation_player.current_animation
	if (current_anim == "Fire" or current_anim == "Crouch_Fire") and animation_player.is_playing() and current_anim != "Move":
		_update_current_target_from_squad()
		activate_muzzle_flash()
		spawn_visual_tracer()

func _update_current_target_from_squad():
	"""Get the current target from the squad unit for accurate firing"""
	var unit = get_parent()
	if not unit:
		return
	
	# Find the squad unit
	var squad_unit = _find_squad_unit()
	if not squad_unit:
		return
	
	# Get the target for this specific unit
	var target = null
	if unit == squad_unit.current_leader:
		target = squad_unit.current_enemy
	else:
		target = squad_unit.clone_targets.get(unit, null)
	
	if target and is_instance_valid(target):
		# Update target information with fresh data
		current_target = target
		target_node = target
		target_position = target.global_position
		shooter_position = unit.global_position
		firing_distance = shooter_position.distance_to(target_position)
		last_fire_time = Time.get_ticks_msec() / 1000.0

func _find_squad_unit():
	"""Find the SquadUnit this muzzle flash belongs to"""
	var node = get_parent()
	while node:
		if node.has_method("get_targeting_debug_info"):  # SquadUnit method
			return node
		# Check if parent has squad_reference meta
		if node.has_meta("squad_reference"):
			return node.get_meta("squad_reference")
		node = node.get_parent()
	return null

func activate_muzzle_flash():
	if emitter:
		emitter.emitting = true
		create_tween().tween_callback(deactivate_muzzle_flash).set_delay(0.1)

func deactivate_muzzle_flash():
	if emitter:
		emitter.emitting = false

# MODIFIED function - animations are now handled by SquadAnimationManager
func fire_at_target(target: Node, distance: float, shooter_pos: Vector3 = Vector3.ZERO):
	if not target or not is_instance_valid(target):
		return
	
	# Store target information for more accurate shooting
	current_target = target
	target_node = target
	target_position = target.global_position
	firing_distance = distance
	last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Use provided shooter position or get from parent
	if shooter_pos != Vector3.ZERO:
		shooter_position = shooter_pos
	else:
		shooter_position = get_parent().global_position
	
	# Only trigger animation if auto mode is enabled
	if auto_trigger_fire_animation and animation_player:
		animation_player.play("Fire")
	else:
		# Just do the visual effects without triggering animation
		# The SquadAnimationManager will handle animations separately
		activate_muzzle_flash()
		spawn_visual_tracer()

func spawn_visual_tracer():
	if not tracer_scene:
		return
	
	var model_node = get_parent()
	if not model_node or not is_instance_valid(model_node):
		return
		
	var start_position = model_node.global_position + model_node.global_transform.basis * muzzle_offset
	
	# SIMPLE APPROACH: Just use the unit's forward direction with slight random spread
	# The centralized animation system ensures units are facing their targets when firing
	var target_direction = model_node.global_transform.basis.z
	
	# Apply small accuracy spread based on distance if we have target info
	var accuracy = 0.9  # Default high accuracy
	if firing_distance > 0:
		accuracy = _calculate_accuracy(firing_distance)
	
	# Apply minimal spread for realism
	target_direction = _apply_accuracy_offset(target_direction, accuracy)
	
	var end_position = start_position + target_direction * tracer_max_distance
	
	var tracer = tracer_scene.instantiate()
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = start_position
	tracer.look_at(end_position, Vector3.UP)
	
	# Set target information on the tracer for damage detection
	if tracer.has_method("set_target_info"):
		tracer.set_target_info(current_target, target_position, firing_distance)
	
	var travel_time = tracer_max_distance / tracer_speed
	var tween = create_tween()
	tween.tween_property(tracer, "global_position", end_position, travel_time)

func _calculate_accuracy(distance: float) -> float:
	# Distance-based accuracy using exported values
	if distance <= short_range_threshold:
		return short_range_accuracy
	elif distance <= medium_range_threshold:
		return medium_range_accuracy
	else:
		return long_range_accuracy

func _apply_accuracy_offset(direction: Vector3, accuracy: float) -> Vector3:
	# Convert accuracy to spread angle (lower accuracy = higher spread)
	var max_spread_angle = deg_to_rad(45.0)  # Maximum 45 degree spread for 0% accuracy
	var spread_angle = max_spread_angle * (1.0 - accuracy)
	
	# Generate random offset within a cone
	var random_angle = randf() * TAU  # Random angle around the cone
	var random_spread = randf() * spread_angle  # Random amount of spread
	
	# Create perpendicular vectors to the main direction
	var up_vector = Vector3.UP
	if abs(direction.dot(up_vector)) > 0.9:
		up_vector = Vector3.RIGHT
	
	var right_vector = direction.cross(up_vector).normalized()
	var actual_up_vector = right_vector.cross(direction).normalized()
	
	# Apply the spread offset
	var offset_right = cos(random_angle) * sin(random_spread)
	var offset_up = sin(random_angle) * sin(random_spread)
	
	var final_direction = direction + (right_vector * offset_right) + (actual_up_vector * offset_up)
	return final_direction.normalized()

# UTILITY: Clear target info (useful for debugging or manual control)
func clear_target():
	current_target = null
	target_node = null
	target_position = Vector3.ZERO
	firing_distance = 0.0

# UTILITY: Get current accuracy for debugging
func get_current_accuracy() -> float:
	return _calculate_accuracy(firing_distance)

# NEW: Manual trigger methods for animation manager to use
func trigger_fire_effects_only():
	"""Trigger only visual effects without animation - called by animation manager"""
	activate_muzzle_flash()
	spawn_visual_tracer()

func trigger_aim_effects():
	"""Trigger any aim-related effects - called by animation manager"""
	# Add any aim-specific visual effects here if needed
	pass

# NEW: Method to be called when Fire animation actually plays
func on_fire_animation_playing():
	"""Called by animation manager when Fire animation is actually playing"""
	_update_current_target_from_squad()
	activate_muzzle_flash()
	spawn_visual_tracer()

# NEW: Configuration methods
func set_auto_animation_mode(fire_anim: bool, aim_anim: bool = false):
	"""Configure whether this muzzle flash should auto-trigger animations"""
	auto_trigger_fire_animation = fire_anim
	auto_trigger_aim_animation = aim_anim
	
	# Reconnect signals if needed
	if animation_player:
		# Disconnect existing signals
		if animation_player.has_signal("animation_started"):
			if animation_player.animation_started.is_connected(_on_animation_started):
				animation_player.animation_started.disconnect(_on_animation_started)
			if animation_player.animation_started.is_connected(_on_animation_started_sync):
				animation_player.animation_started.disconnect(_on_animation_started_sync)
		if animation_player.has_signal("animation_changed"):
			if animation_player.animation_changed.is_connected(_on_animation_changed):
				animation_player.animation_changed.disconnect(_on_animation_changed)
			if animation_player.animation_changed.is_connected(_on_animation_changed_sync):
				animation_player.animation_changed.disconnect(_on_animation_changed_sync)
		
		# Reconnect based on mode
		if auto_trigger_fire_animation:
			if animation_player.has_signal("animation_started"):
				animation_player.animation_started.connect(_on_animation_started)
			else:
				animation_player.animation_changed.connect(_on_animation_changed)
		else:
			# Connect sync methods for centralized animation system
			if animation_player.has_signal("animation_started"):
				animation_player.animation_started.connect(_on_animation_started_sync)
			else:
				animation_player.animation_changed.connect(_on_animation_changed_sync)

# NEW: Debug info
func get_muzzle_flash_info() -> Dictionary:
	return {
		"auto_trigger_fire": auto_trigger_fire_animation,
		"auto_trigger_aim": auto_trigger_aim_animation,
		"has_current_target": current_target != null,
		"current_target_name": current_target.name if current_target else "None",
		"has_stored_target": target_node != null,
		"stored_target_name": target_node.name if target_node else "None",
		"firing_distance": firing_distance,
		"current_accuracy": get_current_accuracy(),
		"last_fire_time": last_fire_time
	}
