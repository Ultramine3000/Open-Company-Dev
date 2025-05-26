extends CharacterBody3D

@export var stats: CombatUnitData
@onready var infantry_template: Node3D = $Infantry
@onready var nav_agent: NavigationAgent3D = $Infantry/NavigationAgent3D
@onready var anim_player: AnimationPlayer = $Infantry/AnimationPlayer
@onready var selection_ring: Node3D = $Infantry/SelectionRing
@onready var unit_bar: Node3D = $UnitBar

var enemy_in_range := false
var is_attacking := false

var current_enemy: Node = null
var attack_timer := 0.0
var attack_interval := 2.0  # time between shots

var total_health : int 
var current_health : float 
var is_dead := false  # At the top of the script

var infantry_clones: Array = []

# Add unique squad identifier
var squad_unique_id: String = ""

var is_selected: bool = false:
	set(value):
		# Don't allow selection if squad is dead
		if is_dead:
			is_selected = false
			return
			
		is_selected = value
		if selection_ring:
			selection_ring.visible = value
		for clone in infantry_clones:
			if is_instance_valid(clone):
				var ring = clone.get_node_or_null("SelectionRing")
				if ring:
					ring.visible = value

# Store formation basis - updated when move commands are issued
var formation_forward: Vector3
var formation_right: Vector3
var last_movement_rotation: float = 0.0

func _ready():
	# Generate unique ID for this squad instance
	squad_unique_id = "Squad_" + str(get_instance_id()) + "_" + str(Time.get_ticks_msec())
	
	# CRITICAL FIX: Ensure each squad has its own unique stats resource
	if stats:
		print("SQUAD CREATED: ", squad_unique_id, " with stats ID: ", stats.get_instance_id())
		
		# Always duplicate the stats resource to prevent cross-squad interference
		var original_stats_id = stats.get_instance_id()
		stats = stats.duplicate()
		stats.resource_local_to_scene = true
		
		print("Stats duplicated from ID ", original_stats_id, " to new ID ", stats.get_instance_id())
	else:
		push_error("No stats assigned to squad: ", squad_unique_id)
		return
	
	if not unit_bar: 
		push_error("Unit Bar Scene missing for ", squad_unique_id)
		return
	
	# Set up unit bar with proper ownership
	if unit_bar and is_instance_valid(unit_bar):
		# Set ownership to prevent cross-squad interference
		unit_bar.squad_owner = self
		unit_bar.name = "UnitBar_" + squad_unique_id  # Make unit bar name unique
		unit_bar.set_albedo_texture(stats.unit_icon)
		
	if anim_player:
		anim_player.play(_get_random_idle_animation())
	if selection_ring:
		selection_ring.visible = false

	# Initialize formation orientation vectors
	formation_forward = -global_transform.basis.z.normalized()
	formation_right = global_transform.basis.x.normalized()
	last_movement_rotation = rotation.y

	if stats:
		_spawn_infantry_clones(stats.squad_size)
		#initialize health data
		total_health = stats.squad_size*stats.health
		current_health = float(total_health)
		print("Squad ", squad_unique_id, " initialized with total health: ", total_health)
	else:
		push_warning("CombatUnitData 'stats' not assigned!")

func _spawn_infantry_clones(count: int):
	var num_clones = count - 1
	var base_spacing = 3.5  # Distance from leader to clones

	var container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if container == null:
		push_error("Missing 'CloneContainer' node in scene.")
		return

	for i in num_clones:
		var clone = infantry_template.duplicate()
		# Make clone names unique per squad
		clone.name = "InfantryClone_%s_%d" % [squad_unique_id, i]

		# Calculate formation offset based on geometric patterns
		var offset = _calculate_formation_offset(i, num_clones, base_spacing)
		
		# Store offset for formation maintenance
		clone.set_meta("formation_offset", offset)
		clone.set_meta("squad_owner", self)  # Track which squad owns this clone
		clone.set_meta("squad_id", squad_unique_id)  # Unique squad identifier
		
		# Use the same health value for all squad members from stats
		clone.set_meta("health", stats.health)  # Initialize health from stats
		clone.set_meta("max_health", stats.health)  # Track max health for potential healing
		clone.set_meta("is_dead", false)  # Track individual clone death state
		
		# Add to container first (but don't show yet)
		clone.visible = false
		container.add_child(clone)
		
		# Now position clone relative to leader's position and orientation
		var leader_forward = -global_transform.basis.z.normalized()
		var leader_right = global_transform.basis.x.normalized()
		var spawn_position = global_transform.origin + leader_right * offset.x + leader_forward * offset.z
		
		# Set clone's global position and rotation directly
		clone.global_transform.origin = spawn_position
		clone.global_rotation = global_rotation
		
		# Now make it visible
		clone.visible = true

		var clone_anim = clone.get_node_or_null("AnimationPlayer")
		if clone_anim:
			clone_anim.play(_get_random_idle_animation())
			
		var ring = clone.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = is_selected

		infantry_clones.append(clone)

func _calculate_formation_offset(clone_index: int, total_clones: int, spacing: float) -> Vector3:
	var offset = Vector3.ZERO
	
	match total_clones:
		1:
			# Single clone - place side by side with leader
			offset = Vector3(spacing, 0, 0)  # Right side of leader
		
		2:
			# Two clones - diamond formation with leader at front point
			var positions = [
				Vector3(-spacing * 0.7, 0, -spacing * 0.7),  # Back-left
				Vector3(spacing * 0.7, 0, -spacing * 0.7)    # Back-right
			]
			offset = positions[clone_index]
		
		3:
			# Three clones - triangular formation behind leader
			var positions = [
				Vector3(-spacing * 0.7, 0, -spacing * 0.7),  # Back-left
				Vector3(spacing * 0.7, 0, -spacing * 0.7),   # Back-right
				Vector3(0, 0, -spacing)                       # Directly behind
			]
			offset = positions[clone_index]
		
		4:
			# Four clones - square formation around leader
			var positions = [
				Vector3(-spacing, 0, 0),    # Left
				Vector3(spacing, 0, 0),     # Right
				Vector3(0, 0, spacing),     # Front
				Vector3(0, 0, -spacing)     # Back
			]
			offset = positions[clone_index]
		
		5:
			# Five clones - pentagon formation around leader
			var angle_step = 2 * PI / 5
			var angle = clone_index * angle_step
			offset = Vector3(
				sin(angle) * spacing,
				0,
				cos(angle) * spacing
			)
		
		6:
			# Six clones - hexagon formation around leader
			var angle_step = 2 * PI / 6
			var angle = clone_index * angle_step
			offset = Vector3(
				sin(angle) * spacing,
				0,
				cos(angle) * spacing
			)
		
		7:
			# Seven clones - hexagon + 1 behind leader
			if clone_index < 6:
				# First 6 in hexagon
				var angle_step = 2 * PI / 6
				var angle = clone_index * angle_step
				offset = Vector3(
					sin(angle) * spacing,
					0,
					cos(angle) * spacing
				)
			else:
				# 7th clone directly behind
				offset = Vector3(0, 0, -spacing * 1.5)
		
		8:
			# Eight clones - octagon formation around leader
			var angle_step = 2 * PI / 8
			var angle = clone_index * angle_step
			offset = Vector3(
				sin(angle) * spacing,
				0,
				cos(angle) * spacing
			)
		
		_:
			# For larger squads (9+), use double ring formation
			if clone_index < 6:
				# Inner ring - hexagon
				var angle_step = 2 * PI / 6
				var angle = clone_index * angle_step
				offset = Vector3(
					sin(angle) * spacing * 0.7,
					0,
					cos(angle) * spacing * 0.7
				)
			else:
				# Outer ring - remaining clones in larger circle
				var remaining_clones = total_clones - 6
				var outer_index = clone_index - 6
				var angle_step = 2 * PI / remaining_clones
				var angle = outer_index * angle_step
				offset = Vector3(
					sin(angle) * spacing * 1.3,
					0,
					cos(angle) * spacing * 1.3
				)
	
	# Add slight random variation to prevent perfect overlap
	offset.x += randf_range(-0.2, 0.2)
	offset.z += randf_range(-0.2, 0.2)
	
	return offset

func _physics_process(delta):
	# Don't process if we're dead
	if is_dead:
		return
		
	# Don't process if we're dead/being destroyed
	if stats.health <= 0:
		if not is_dead:  # Only trigger death sequence once
			is_dead = true
			print("TRIGGERING DEATH for squad: ", squad_unique_id, " with stats ID: ", stats.get_instance_id())
			_handle_squad_death()
		return
		
	if nav_agent == null:
		return

	var is_moving = not nav_agent.is_navigation_finished()

	# Check if we have any valid clones remaining
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			# Verify clone belongs to this squad
			var clone_squad_id = clone.get_meta("squad_id", "")
			if clone_squad_id != squad_unique_id:
				continue  # Skip clones that don't belong to this squad
			# Also check if clone is dead
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:
				valid_clones.append(clone)
	
	# Clean up infantry_clones array if needed
	if valid_clones.size() != infantry_clones.size():
		infantry_clones = valid_clones.duplicate()

	# If we're moving, pause attacking but still track enemies
	if is_moving:
		is_attacking = false  # Cancel any current attack if moving
		attack_timer = 0.0    # Reset attack timer
		
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_transform.origin).normalized()

		if direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * 8.0)

		velocity = direction * stats.move_speed
		move_and_slide()

		if anim_player.current_animation != "Move":
			anim_player.play("Move")
	else:
		# Allow leader to rotate toward enemy during combat
		if enemy_in_range and current_enemy and is_instance_valid(current_enemy) and not is_moving:
			var direction_to_enemy = current_enemy.global_transform.origin - global_transform.origin
			direction_to_enemy.y = 0  # Keep on the same plane
			
			if direction_to_enemy.length() > 0.1:
				var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
				
				# If we're not attacking currently, ensure we're in a combat-ready stance
				if not is_attacking and anim_player.current_animation != "Aim":
					anim_player.play("Aim")
					
		velocity = Vector3.ZERO
		move_and_slide()  # Still call this to apply any lingering velocity

		# Only return to idle if not in combat and not moving
		if not enemy_in_range and anim_player.current_animation != "Idle_1" and anim_player.current_animation != "Idle_2":
			anim_player.play(_get_random_idle_animation())
		elif enemy_in_range and not is_attacking and anim_player.current_animation != "Aim" and anim_player.current_animation != "Fire":
			anim_player.play("Aim")

	# Only process clone movement if we have clones
	if infantry_clones.size() > 0:
		_process_clone_movement(delta)
		
	_check_for_nearby_enemies()

	# Only process combat if not moving and enemy is in range
	if enemy_in_range and not is_moving and not is_attacking:
		attack_timer += delta
		
		# Adjust attack interval based on squad size for balance
		# Smaller squads fire faster to compensate for fewer shots
		var living_size = get_living_squad_size()
		var adjusted_interval = attack_interval
		if living_size <= 2:
			adjusted_interval = attack_interval * 0.7  # 30% faster for small squads
		elif living_size >= 5:
			adjusted_interval = attack_interval * 1.3  # 30% slower for large squads
			
		if attack_timer >= adjusted_interval:
			attack_timer = 0.0
			_perform_attack()

func _clone_play_animation(clone: Node3D, anim_name: String):
	# More thorough validation to prevent errors with freed objects
	if clone == null or not is_instance_valid(clone) or clone.is_queued_for_deletion():
		return
	
	# Verify clone belongs to this squad
	var clone_squad_id = clone.get_meta("squad_id", "")
	if clone_squad_id != squad_unique_id:
		return  # Don't control clones from other squads
	
	# Check if this clone is dead
	var clone_is_dead = clone.get_meta("is_dead", false)
	if clone_is_dead:
		return
		
	# Make sure the clone still has an animation player
	var clone_anim = clone.get_node_or_null("AnimationPlayer")
	if clone_anim != null and is_instance_valid(clone_anim) and clone_anim.has_animation(anim_name):
		clone_anim.play(anim_name)

func _process_clone_movement(delta):
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			# Verify clone belongs to this squad
			var clone_squad_id = clone.get_meta("squad_id", "")
			if clone_squad_id != squad_unique_id:
				continue  # Skip clones from other squads
			if not clone.get_meta("is_dead", false):
				valid_clones.append(clone)

	if valid_clones.size() != infantry_clones.size():
		infantry_clones = valid_clones.duplicate()

	var is_moving = not nav_agent.is_navigation_finished()

	if is_moving and abs(rotation.y - last_movement_rotation) > 0.05:
		formation_forward = -global_transform.basis.z.normalized()
		formation_right = global_transform.basis.x.normalized()
		last_movement_rotation = rotation.y

	for clone in valid_clones:
		var offset: Vector3 = clone.get_meta("formation_offset")
		var target_pos = global_transform.origin + formation_right * offset.x + formation_forward * offset.z
		var move_vec = target_pos - clone.global_transform.origin
		move_vec.y = 0
		var distance = move_vec.length()

		var clone_anim = clone.get_node_or_null("AnimationPlayer")
		var clone_moving = is_moving or distance > 0.25

		if clone_moving:
			if clone_anim and clone_anim.current_animation != "Move":
				clone_anim.play("Move")

			var move_step = move_vec.normalized() * min(distance, stats.move_speed * delta)
			clone.global_translate(move_step)

			if distance > 0.1:
				var target_rot = atan2(move_vec.x, move_vec.z)
				clone.rotation.y = lerp_angle(clone.rotation.y, target_rot, delta * 4.0)

		elif enemy_in_range and current_enemy and is_instance_valid(current_enemy):
			var direction_to_enemy = current_enemy.global_transform.origin - clone.global_transform.origin
			direction_to_enemy.y = 0

			if direction_to_enemy.length() > 0.1:
				var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
				clone.rotation.y = lerp_angle(clone.rotation.y, target_rotation, delta * 4.0)

			if clone_anim and clone_anim.current_animation not in ["Aim", "Fire"]:
				clone_anim.play("Aim")

			if distance > 0.05:
				var combat_move_step = move_vec.normalized() * min(distance, stats.move_speed * 0.5 * delta)
				clone.global_translate(combat_move_step)
		else:
			if clone_anim and clone_anim.current_animation not in ["Idle_1", "Idle_2"]:
				clone_anim.play(_get_random_idle_animation())

		# Snap to position to avoid jitter
		if distance < 0.05 and not enemy_in_range:
			clone.global_transform.origin = target_pos

		# Collision avoidance: too close to leader
		var to_leader = clone.global_transform.origin - global_transform.origin
		to_leader.y = 0
		var dist_to_leader = to_leader.length()
		if dist_to_leader < 1.5:
			var push_away = to_leader.normalized() * (1.5 - dist_to_leader)
			clone.global_translate(push_away * delta * 4.0)

		# Collision avoidance: too close to other clones
		for other_clone in infantry_clones:
			if other_clone == clone or not is_instance_valid(other_clone):
				continue

			var to_other = clone.global_transform.origin - other_clone.global_transform.origin
			to_other.y = 0
			var dist = to_other.length()
			if dist < 1.2:
				var push_dir = to_other.normalized()
				var push_strength = (1.2 - dist)
				clone.global_translate(push_dir * push_strength * delta * 3.5)

		# Match leader's Y height
		var new_pos = clone.global_transform.origin
		new_pos.y = global_transform.origin.y + 0.1
		clone.global_transform.origin = new_pos

func move_to_position(pos: Vector3):
	# Don't accept move commands if dead
	if is_dead:
		return
		
	if nav_agent:
		nav_agent.set_target_position(pos)
		
		# Reset attack state when ordered to move
		attack_timer = 0.0
		if is_attacking:
			is_attacking = false
		
		# Update formation orientation when movement starts
		# This allows the formation to rotate as a whole to face the new direction
		var direction = (pos - global_transform.origin).normalized()
		if direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			
			# Calculate new formation orientation vectors based on target direction
			# We do this immediately so the formation updates its orientation at the start of movement
			var angle_change = target_rotation - rotation.y
			formation_forward = Vector3(sin(target_rotation), 0, cos(target_rotation)).normalized()
			formation_right = Vector3(cos(target_rotation), 0, -sin(target_rotation)).normalized()
			last_movement_rotation = target_rotation
			
		# Switch to movement animation
		if anim_player and anim_player.current_animation != "Move":
			anim_player.play("Move")
			
		# Apply movement animation to clones as well
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				# Verify clone belongs to this squad
				var clone_squad_id = clone.get_meta("squad_id", "")
				if clone_squad_id != squad_unique_id:
					continue
				var clone_is_dead = clone.get_meta("is_dead", false)
				if not clone_is_dead:
					var clone_anim = clone.get_node_or_null("AnimationPlayer")
					if clone_anim and clone_anim.current_animation != "Move":
						clone_anim.play("Move")
		
		# Only clear enemy target if we're moving away from combat
		var dist_to_target = global_transform.origin.distance_to(pos)
		if dist_to_target > 5.0:  # Only disengage if moving a significant distance
			current_enemy = null
			enemy_in_range = false

func _check_for_nearby_enemies():
	var opposing_group = "allies" if is_in_group("axis") else "axis"
	var closest_enemy = null
	var closest_distance = INF
	
	var detection_range = stats.vision_range if stats and stats.get("vision_range") != null else 20.0

	for node in get_tree().get_nodes_in_group(opposing_group):
		if not node is CharacterBody3D or not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and node.is_dead:
			continue
		var dist = global_transform.origin.distance_to(node.global_transform.origin)
		if dist <= detection_range and dist < closest_distance:
			if _has_line_of_sight(self, node):  # Only set if LoS exists
				closest_enemy = node
				closest_distance = dist

	if closest_enemy:
		if not enemy_in_range or current_enemy != closest_enemy:
			enemy_in_range = true
			current_enemy = closest_enemy

			if anim_player and anim_player.has_animation("Aim"):
				anim_player.play("Aim")
				
			for clone in infantry_clones.duplicate():
				if is_instance_valid(clone) and not clone.is_queued_for_deletion():
					# Verify clone belongs to this squad
					var clone_squad_id = clone.get_meta("squad_id", "")
					if clone_squad_id != squad_unique_id:
						continue
					var clone_is_dead = clone.get_meta("is_dead", false)
					if not clone_is_dead and _has_line_of_sight(clone, closest_enemy):  # Only aim if LoS
						_clone_play_animation(clone, "Aim")
	else:
		if enemy_in_range:
			enemy_in_range = false
			current_enemy = null
			
			if anim_player:
				anim_player.play(_get_random_idle_animation())
				
			for clone in infantry_clones.duplicate():
				if is_instance_valid(clone) and not clone.is_queued_for_deletion():
					# Verify clone belongs to this squad
					var clone_squad_id = clone.get_meta("squad_id", "")
					if clone_squad_id != squad_unique_id:
						continue
					var clone_is_dead = clone.get_meta("is_dead", false)
					if not clone_is_dead:
						_clone_play_animation(clone, _get_random_idle_animation())

# Check if a unit (leader or clone) has line of sight to the target
func _has_line_of_sight(unit: Node3D, target: Node3D) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(target):
		return false
	
	# Look for Vision node - check different possible locations
	var vision_node = null
	
	# First try direct child of the unit
	vision_node = unit.get_node_or_null("Vision")
	
	# If not found, try inside Infantry subfolder (for leader)
	if not vision_node and unit == self:
		vision_node = infantry_template.get_node_or_null("Vision")
	
	# If still no Vision node found, use unit's global position as fallback
	var raycast_origin: Vector3
	if vision_node:
		raycast_origin = vision_node.global_transform.origin
	else:
		# Fallback: use unit position with slight height offset for "eye level"
		raycast_origin = unit.global_transform.origin + Vector3(0, 1.8, 0)
	
	# Target the center mass of the enemy (add height offset)
	var raycast_target = target.global_transform.origin + Vector3(0, 1.0, 0)
	
	# Calculate direction and distance
	var direction = (raycast_target - raycast_origin).normalized()
	var distance = raycast_origin.distance_to(raycast_target)
	
	# Create raycast query
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(raycast_origin, raycast_target)
	
	# Exclude self and friendly units from blocking line of sight
	var exclusions = [unit]  # Always exclude the firing unit
	
	# Exclude all friendly squad members
	exclusions.append(self)  # Exclude leader
	for clone in infantry_clones:
		if is_instance_valid(clone):
			exclusions.append(clone)
	
	# Exclude other friendly squads in the same group
	var friendly_group = "allies" if is_in_group("allies") else "axis"
	for friendly_unit in get_tree().get_nodes_in_group(friendly_group):
		if friendly_unit != self and is_instance_valid(friendly_unit):
			exclusions.append(friendly_unit)
	
	query.exclude = exclusions
	
	# Perform the raycast
	var result = space_state.intersect_ray(query)
	
	# If nothing hit, line of sight is clear
	if result.is_empty():
		return true
	
	# If we hit the target enemy, line of sight is clear
	if result.get("collider") == target:
		return true
	
	# If we hit something else, line of sight is blocked
	return false

# Modified _perform_attack function with line of sight checks
func _perform_attack():
	if not current_enemy or not is_instance_valid(current_enemy) or is_dead:
		is_attacking = false
		return
		
	is_attacking = true

	# Allow leader to rotate during attack like during normal combat
	if is_instance_valid(current_enemy):
		var direction_to_enemy = current_enemy.global_transform.origin - global_transform.origin
		direction_to_enemy.y = 0  # Keep on the same plane
		
		if direction_to_enemy.length() > 0.1:
			var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 0.5)  # Quick rotation for attack

	# Check if leader has line of sight before aiming
	var leader_can_fire = _has_line_of_sight(self, current_enemy)
	
	# Aim anims for leader (only if can fire)
	if leader_can_fire and anim_player and anim_player.has_animation("Aim"):
		anim_player.play("Aim")

	# Make a safe copy of the clones array and check line of sight for each
	var valid_clones = []
	var clones_can_fire = []
	
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			# Verify clone belongs to this squad
			var clone_squad_id = clone.get_meta("squad_id", "")
			if clone_squad_id != squad_unique_id:
				continue
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:
				valid_clones.append(clone)
				var can_fire = _has_line_of_sight(clone, current_enemy)
				clones_can_fire.append(can_fire)
				
				# Only play aim animation if clone can fire
				if can_fire:
					_clone_play_animation(clone, "Aim")

	# CRITICAL FIX: Store attack state before await to check if squad died during wait
	var attack_id = randi()  # Generate unique attack ID
	set_meta("current_attack_id", attack_id)
	
	await get_tree().create_timer(0.3).timeout

	# Check if squad died during the aim delay OR if this attack is outdated
	if is_dead or get_meta("current_attack_id", -1) != attack_id:
		is_attacking = false
		return

	# Fire anims for leader (only if can fire)
	if leader_can_fire and anim_player and anim_player.has_animation("Fire") and is_instance_valid(current_enemy):
		anim_player.play("Fire")

	# Calculate squad strength based on units that can actually fire
	var firing_squad_strength = 0
	if leader_can_fire and stats.health > 0:
		firing_squad_strength += 1

	# Fire anims for clones that can fire - more staggered timing
	for i in range(valid_clones.size()):
		# Check if squad died during the firing sequence OR attack is outdated
		if is_dead or get_meta("current_attack_id", -1) != attack_id:
			is_attacking = false
			return
			
		var clone = valid_clones[i]
		var can_fire = clones_can_fire[i]
		
		if not can_fire:
			continue
			
		if not is_instance_valid(clone) or clone.is_queued_for_deletion():
			continue
			
		# Check if this specific clone died during the attack
		var clone_is_dead = clone.get_meta("is_dead", false)
		if clone_is_dead:
			continue
			
		firing_squad_strength += 1
			
		# Increased stagger time and made it more varied
		var stagger_time = 0.75 + (0.1 * (i % 4)) + randf_range(0.0, 0.1)
		if stagger_time > 0:
			await get_tree().create_timer(stagger_time).timeout
			
		# Check again after the timer in case squad died during wait OR attack is outdated
		if is_dead or get_meta("current_attack_id", -1) != attack_id:
			is_attacking = false
			return
			
		# Final check if clone is still alive
		clone_is_dead = clone.get_meta("is_dead", false)
		if not clone_is_dead:
			_clone_play_animation(clone, "Fire")

	# Combat logic only performed by leader, but damage based on units that can actually fire
	if current_enemy and is_instance_valid(current_enemy) and firing_squad_strength > 0:
		var distance = global_transform.origin.distance_to(current_enemy.global_transform.origin)
		var accuracy = 0.0
		if distance <= 15.0:
			accuracy = stats.short_range_accuracy
		elif distance <= 30.0:
			accuracy = stats.medium_range_accuracy
		else:
			accuracy = stats.long_range_accuracy

		# Only units with line of sight can fire
		for i in range(firing_squad_strength):
			if randf() <= accuracy:
				# Each successful hit only deals 1 damage
				if current_enemy.has_method("take_damage"):
					current_enemy.take_damage(1)
					
					# Check if enemy squad is dead after each shot to avoid overkill
					if current_enemy.has_method("is_squad_dead") and current_enemy.is_squad_dead():
						break
					elif "is_dead" in current_enemy and current_enemy.is_dead:
						break

	await get_tree().create_timer(0.5).timeout  # Give time for anims to finish
	
	# Final check - don't continue if squad died during the attack sequence OR attack is outdated
	if is_dead or get_meta("current_attack_id", -1) != attack_id:
		is_attacking = false
		return
	
	# Make sure we're still in combat stance after attack finishes (if still alive and enemy present)
	if is_instance_valid(current_enemy) and enemy_in_range and stats.health > 0:
		# Only leader aims if they can fire
		if leader_can_fire and anim_player and anim_player.has_animation("Aim"):
			anim_player.play("Aim")
			
		# Only clones that can fire should aim
		for i in range(valid_clones.size()):
			var clone = valid_clones[i]
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				var clone_is_dead = clone.get_meta("is_dead", false)
				var can_fire = _has_line_of_sight(clone, current_enemy)  # Re-check in case situation changed
				if not clone_is_dead and can_fire:
					_clone_play_animation(clone, "Aim")
	
	is_attacking = false

# Helper function to check if entire squad is dead
func is_squad_dead() -> bool:
	if is_dead:
		return true
		
	# Check if leader is dead
	if stats.health <= 0:
		return true
		
	# Check if any clones are alive
	for clone in infantry_clones:
		if is_instance_valid(clone):
			var clone_is_dead = clone.get_meta("is_dead", false)
			var clone_health = clone.get_meta("health", 0)
			if not clone_is_dead and clone_health > 0:
				return false
	
	return true

# Helper function to get squad size (living members only)
func get_living_squad_size() -> int:
	var living_count = 0
	
	# Count leader if alive
	if stats.health > 0 and not is_dead:
		living_count += 1
		
	# Count living clones
	for clone in infantry_clones:
		if is_instance_valid(clone):
			var clone_is_dead = clone.get_meta("is_dead", false)
			var clone_health = clone.get_meta("health", 0)
			if not clone_is_dead and clone_health > 0:
				living_count += 1
				
	return living_count

# Helper function to get a random idle animation
func _get_random_idle_animation() -> String:
	var idle_anims = ["Idle_1", "Idle_2"]
	return idle_anims[randi() % idle_anims.size()]

# Helper function to get a random death animation
func _get_random_death_animation() -> String:
	var death_anims = ["Death_1", "Death_2", "Death_3"]
	return death_anims[randi() % death_anims.size()]

func _play_death_animation(unit: Node3D) -> void:
	var anim_player_node = null
	
	# Handle different node structures - leader vs clones
	if unit == self:
		# For the leader, use the stored anim_player reference
		anim_player_node = anim_player
	else:
		# For clones, look for AnimationPlayer as direct child
		anim_player_node = unit.get_node_or_null("AnimationPlayer")
	
	if not anim_player_node:
		push_error("No animation player found for death animation")
		return
	
	# CRITICAL FIX: Force stop any current animation and immediately clear animation queue
	anim_player_node.stop(true)  # true parameter clears the animation queue
	anim_player_node.seek(0.0, true)  # Reset to beginning and update immediately
	
	# Wait one frame to ensure the stop took effect
	await get_tree().process_frame
	
	var death_anim = _get_random_death_animation()
	
	# Check if the animation exists, fallback to others if not
	if anim_player_node.has_animation(death_anim):
		anim_player_node.play(death_anim)
	elif anim_player_node.has_animation("Death_1"):
		anim_player_node.play("Death_1")
		death_anim = "Death_1"
	elif anim_player_node.has_animation("Death_2"):
		anim_player_node.play("Death_2")
		death_anim = "Death_2"
	elif anim_player_node.has_animation("Death_3"):
		anim_player_node.play("Death_3")
		death_anim = "Death_3"
	else:
		# No death animation available
		push_error("No death animations available!")

# Add this function to check if squad is in cover
func _is_in_cover() -> bool:
	# Only check for cover if we have an enemy and are in combat
	if not current_enemy or not is_instance_valid(current_enemy):
		return false
	
	# Find the closest Heavy_Cover node
	var closest_cover = null
	var closest_cover_distance = INF
	var cover_nodes = get_tree().get_nodes_in_group("Heavy_Cover")
	
	for cover_node in cover_nodes:
		if not is_instance_valid(cover_node):
			continue
			
		var distance_to_cover = global_transform.origin.distance_to(cover_node.global_transform.origin)
		if distance_to_cover < closest_cover_distance:
			closest_cover = cover_node
			closest_cover_distance = distance_to_cover
	
	# Check if we found cover and are close enough to it
	if not closest_cover or closest_cover_distance > 5.0:
		return false
	
	# Check if the cover is between us and the enemy
	var squad_pos = global_transform.origin
	var enemy_pos = current_enemy.global_transform.origin
	var cover_pos = closest_cover.global_transform.origin
	
	# Calculate distances
	var squad_to_enemy_distance = squad_pos.distance_to(enemy_pos)
	var squad_to_cover_distance = squad_pos.distance_to(cover_pos)
	var cover_to_enemy_distance = cover_pos.distance_to(enemy_pos)
	
	# Cover is "between" if squad->cover + cover->enemy ≈ squad->enemy
	# Allow some tolerance for positioning
	var total_through_cover = squad_to_cover_distance + cover_to_enemy_distance
	var tolerance = 3.0  # meters of tolerance
	
	# Also check angle - cover should be roughly in the direction of the enemy
	var squad_to_enemy_vec = (enemy_pos - squad_pos).normalized()
	var squad_to_cover_vec = (cover_pos - squad_pos).normalized()
	var angle_dot = squad_to_enemy_vec.dot(squad_to_cover_vec)
	
	# Cover is effective if:
	# 1. It's roughly between squad and enemy (within tolerance)
	# 2. It's in the general direction of the enemy (dot product > 0.3, roughly 70 degrees)
	return (total_through_cover <= squad_to_enemy_distance + tolerance) and (angle_dot > 0.3)

# FIXED: Safe health bar update function
func _safe_update_health_bar():
	if unit_bar and is_instance_valid(unit_bar):
		# Verify ownership before updating
		if "squad_owner" in unit_bar and unit_bar.squad_owner == self:
			unit_bar.set_health_bar(current_health / total_health)
		elif unit_bar.has_method("is_owned_by") and unit_bar.is_owned_by(self):
			unit_bar.set_health_bar(current_health / total_health)
		else:
			push_warning("Health bar update rejected - wrong owner for squad: ", squad_unique_id)

# Modified take_damage function with cover system and ownership verification
func take_damage(amount: int):
	print("DAMAGE RECEIVED: ", amount, " to squad: ", squad_unique_id, " (Stats ID: ", stats.get_instance_id(), ", Health: ", stats.health, ")")
	
	# Don't take damage if already dead or if this squad is marked as destroyed
	if is_dead or is_in_group("dead_squads"):
		print("DAMAGE IGNORED - Squad already dead: ", squad_unique_id)
		return
	
	# Additional safety check - verify this is a valid squad
	if not stats or not is_instance_valid(self):
		print("DAMAGE IGNORED - Invalid squad: ", squad_unique_id)
		return
	
	# Check if squad is in cover and apply damage reduction
	var effective_damage = amount
	var in_cover = _is_in_cover()
	
	if in_cover:
		# 50% chance to completely avoid each point of damage when in cover
		# This simulates bullets hitting cover instead of the squad
		var avoided_damage = 0
		for i in range(amount):
			if randf() < 0.5:  # 50% chance to avoid each damage point
				avoided_damage += 1
		
		effective_damage = amount - avoided_damage
		
		# Optional: Add visual feedback for cover
		if avoided_damage > 0:
			print("Squad taking cover! ", avoided_damage, " damage avoided, ", effective_damage, " damage taken")
		else:
			print("Squad in cover but took full damage this time!")
	
	# Process each point of effective damage individually
	for damage_point in range(effective_damage):
		# Check if squad is already dead
		if is_dead:
			print("Squad died during damage processing: ", squad_unique_id)
			break
			
		# Get current valid clones for this damage point
		var valid_clones = []
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				# Verify clone belongs to this squad
				var clone_squad_id = clone.get_meta("squad_id", "")
				if clone_squad_id != squad_unique_id:
					continue  # Skip clones that don't belong to this squad
					
				var clone_is_dead = false
				var clone_health = 0
				
				# Safe property access for clone death status
				if clone.has_meta("is_dead"):
					clone_is_dead = clone.get_meta("is_dead")
				
				# Safe property access for clone health
				if clone.has_meta("health"):
					clone_health = clone.get_meta("health")
				
				if not clone_is_dead and clone_health > 0:
					valid_clones.append(clone)
		
		# PRIORITY SYSTEM: Target clones first, leader only when no clones remain
		if valid_clones.size() > 0:
			# Damage goes to a random clone (leader is protected while clones exist)
			var clone_index = randi() % valid_clones.size()
			var clone = valid_clones[clone_index]
			var hp = clone.get_meta("health")
			hp -= 1
			clone.set_meta("health", hp)
			current_health -= 1
			
			print("CLONE DAMAGED: Squad ", squad_unique_id, " clone health: ", hp)
			
			# Update health bar with ownership verification
			_safe_update_health_bar()
			
			if hp <= 0:
				print("CLONE KILLED: Squad ", squad_unique_id)
				_handle_clone_death(clone)
		elif stats.health > 0:
			# Only target leader when no clones remain
			stats.health -= 1
			current_health -= 1
			
			print("LEADER DAMAGED: Squad ", squad_unique_id, " leader health: ", stats.health, " (Stats ID: ", stats.get_instance_id(), ")")
			
			# Update health bar with ownership verification
			_safe_update_health_bar()
			
			if stats.health <= 0:
				print("LEADER KILLED - TRIGGERING SQUAD DEATH: ", squad_unique_id, " (Stats ID: ", stats.get_instance_id(), ")")
				# Leader is dead, trigger death sequence
				if not is_dead:
					is_dead = true
					_handle_squad_death()
				return
		else:
			# No valid targets remain
			print("NO VALID TARGETS: Squad ", squad_unique_id)
			break

# Optional: Add a function to get cover status for UI or debugging
func get_cover_status() -> String:
	if _is_in_cover():
		return "IN COVER"
	else:
		return "EXPOSED"

# Optional: Visual indicator for cover (add this to _physics_process if you want real-time feedback)
func _update_cover_visual():
	# You could change unit colors, add shields, or show cover icons
	# This is just an example of how you might implement visual feedback
	if _is_in_cover():
		# Squad is in cover - could tint them blue or add a shield icon
		pass
	else:
		# Squad is exposed - normal appearance
		pass

# FIXED: Only handle clones that belong to THIS squad
func _handle_clone_death(clone: Node3D):
	if not is_instance_valid(clone):
		return
	
	# Verify this clone belongs to this squad
	var clone_squad_id = clone.get_meta("squad_id", "")
	if clone_squad_id != squad_unique_id:
		push_warning("Attempted to kill clone from different squad!")
		return
	
	print("CLONE DEATH: Squad ", squad_unique_id, " killing clone with ID ", clone_squad_id)
	
	# Mark clone as dead IMMEDIATELY to prevent further processing
	clone.set_meta("is_dead", true)
	
	# Disable the clone's collision and movement while playing death animation
	var collision_shape = clone.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true
	
	# Hide selection ring if visible
	var ring = clone.get_node_or_null("SelectionRing")
	if ring:
		ring.visible = false
	
	# Remove from this squad's array immediately
	infantry_clones.erase(clone)
	
	# Play death animation - this now properly handles stopping current animations
	_play_death_animation(clone)

# FIXED: Enhanced squad death with proper ownership verification
func _handle_squad_death():
	print("=== SQUAD DEATH TRIGGERED ===")
	print("Squad ID: ", squad_unique_id)
	print("Stats ID: ", stats.get_instance_id() if stats else "NO STATS")
	print("Stats health: ", stats.health if stats else "NO STATS")
	
	# IMMEDIATELY stop any ongoing attack sequence and invalidate future ones
	is_attacking = false
	set_meta("current_attack_id", -1)  # Invalidate any ongoing attack sequences
	
	# Stop all combat states and animations
	current_enemy = null
	enemy_in_range = false
	
	# Disable leader's collision to prevent further interactions
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true
	
	# Permanently hide selection ring for THIS squad only
	if selection_ring and is_instance_valid(selection_ring):
		selection_ring.visible = false
	
	# Play death animation for the leader
	_play_death_animation(self)
	
	# Handle remaining clones with death animations - only THIS squad's clones
	var clones_copy = infantry_clones.duplicate()  # Make a copy to avoid modification during iteration
	print("Processing ", clones_copy.size(), " clones for squad: ", squad_unique_id)
	for clone in clones_copy:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			var clone_squad_id = clone.get_meta("squad_id", "")
			if clone_squad_id == squad_unique_id:  # Only kill our own clones
				var clone_is_dead = clone.get_meta("is_dead", false)
				if not clone_is_dead:
					print("Killing clone for squad: ", squad_unique_id)
					_handle_clone_death(clone)
			else:
				print("SKIPPING clone with different squad ID: ", clone_squad_id, " (expected: ", squad_unique_id, ")")

	# CRITICAL FIX: Proper unit bar deletion with ownership verification
	if unit_bar and is_instance_valid(unit_bar):
		print("Attempting to delete unit bar for squad: ", squad_unique_id)
		# Check if this unit bar actually belongs to this squad
		if "squad_owner" in unit_bar and unit_bar.squad_owner == self:
			print("OWNERSHIP VERIFIED - Deleting unit bar for: ", squad_unique_id)
			unit_bar.delete_unit_bar()
		elif unit_bar.has_method("is_owned_by") and unit_bar.is_owned_by(self):
			print("BACKUP OWNERSHIP VERIFIED - Deleting unit bar for: ", squad_unique_id)
			unit_bar.delete_unit_bar()
		else:
			# If ownership is unclear, just hide it instead of deleting
			print("OWNERSHIP FAILED - NOT deleting unit bar for: ", squad_unique_id)
			unit_bar.visible = false
			push_warning("Could not verify unit bar ownership for squad: ", squad_unique_id)
	
	# Remove only THIS squad from combat groups
	if is_in_group("allies"):
		remove_from_group("allies")
		print("Removed ", squad_unique_id, " from allies group")
	if is_in_group("axis"):
		remove_from_group("axis")
		print("Removed ", squad_unique_id, " from axis group")
	
	# Add to dead squads group to prevent further targeting
	add_to_group("dead_squads")
	print("Added ", squad_unique_id, " to dead_squads group")
	print("=== END SQUAD DEATH ===")
