extends CharacterBody3D

@export var stats: CombatUnitData

@onready var infantry_template: Node3D = $Infantry
@onready var nav_agent: NavigationAgent3D = $Infantry/NavigationAgent3D
@onready var anim_player: AnimationPlayer = $Infantry/AnimationPlayer
@onready var selection_ring: Node3D = $Infantry/SelectionRing

var enemy_in_range := false
var is_attacking := false

var current_enemy: Node = null
var attack_timer := 0.0
var attack_interval := 2.0  # time between shots

var infantry_clones: Array = []
var is_selected: bool = false:
	set(value):
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
	if anim_player:
		anim_player.play("Idle_1")
	if selection_ring:
		selection_ring.visible = false

	# Initialize formation orientation vectors
	formation_forward = -global_transform.basis.z.normalized()
	formation_right = global_transform.basis.x.normalized()
	last_movement_rotation = rotation.y

	if stats:
		_spawn_infantry_clones(stats.squad_size)
	else:
		push_warning("CombatUnitData 'stats' not assigned!")

func _spawn_infantry_clones(count: int):
	var num_clones = count - 1
	var spacing = 3.9

	var container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if container == null:
		push_error("Missing 'CloneContainer' node in scene.")
		return

	for i in num_clones:
		var clone = infantry_template.duplicate()
		clone.name = "InfantryClone_%d" % i

		var row = i / 3
		var col = i % 3
		
		# Calculate formation offset relative to leader
		var offset = Vector3(
			(col - 1) * spacing + randf_range(-0.5, 0.5),
			0,
			-(row + 1) * spacing + randf_range(-0.5, 0.5)
		)
		
		# Store offset for formation maintenance
		clone.set_meta("formation_offset", offset)
		
		# Use the same health value for all squad members from stats
		clone.set_meta("health", stats.health)  # Initialize health from stats
		clone.set_meta("max_health", stats.health)  # Track max health for potential healing
		
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
			clone_anim.play("Idle_1")
			
		var ring = clone.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = is_selected

		infantry_clones.append(clone)

func _physics_process(delta):
	if nav_agent == null:
		return

	var is_moving = not nav_agent.is_navigation_finished()

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
		if not enemy_in_range and anim_player.current_animation != "Idle_1":
			anim_player.play("Idle_1")
		elif enemy_in_range and not is_attacking and anim_player.current_animation != "Aim" and anim_player.current_animation != "Fire":
			anim_player.play("Aim")

	_process_clone_movement(delta)
	_check_for_nearby_enemies()

	# Only process combat if not moving and enemy is in range
	if enemy_in_range and not is_moving and not is_attacking:
		attack_timer += delta
		if attack_timer >= attack_interval:
			attack_timer = 0.0
			_perform_attack()

func _clone_play_animation(clone: Node3D, anim_name: String):
	# More thorough validation to prevent errors with freed objects
	if clone == null or not is_instance_valid(clone) or clone.is_queued_for_deletion():
		return
		
	# Make sure the clone still has an animation player
	var clone_anim = clone.get_node_or_null("AnimationPlayer")
	if clone_anim != null and is_instance_valid(clone_anim) and clone_anim.has_animation(anim_name):
		clone_anim.play(anim_name)

func _process_clone_movement(delta):
	# Create a safe copy of the infantry_clones array to avoid modification during iteration
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			valid_clones.append(clone)
			
	# Clean up our actual array if needed
	if valid_clones.size() != infantry_clones.size():
		infantry_clones = valid_clones.duplicate()
	
	# Check if we're currently moving
	var is_moving = not nav_agent.is_navigation_finished()
	
	# If moving, check if formation orientation needs updating
	if is_moving and abs(rotation.y - last_movement_rotation) > 0.1:
		# Leader has rotated significantly during movement, update formation orientation
		formation_forward = -global_transform.basis.z.normalized()
		formation_right = global_transform.basis.x.normalized()
		last_movement_rotation = rotation.y
	
	for clone in valid_clones:
		var clone_anim_player = clone.get_node_or_null("AnimationPlayer")
		var offset: Vector3 = clone.get_meta("formation_offset")
		
		# Use the formation vectors that update during movement but stay fixed during combat
		var target_pos = global_transform.origin + formation_right * offset.x + formation_forward * offset.z
		var move_vec = target_pos - clone.global_transform.origin
		move_vec.y = 0
		var distance = move_vec.length()
		
		# Determine if this specific clone is still moving
		var clone_moving = is_moving || distance > 0.25
		
		if clone_moving:
			# Keep move animation playing until clone reaches position
			if clone_anim_player and clone_anim_player.current_animation != "Move":
				clone_anim_player.play("Move")
		
			# Move toward formation target
			clone.global_translate(move_vec.normalized() * stats.move_speed * 0.9 * delta)
			
			# Set rotation to match movement direction
			if move_vec.length() > 0.1:
				var target_rot = atan2(move_vec.x, move_vec.z)
				var current_rot = clone.rotation.y
				clone.rotation.y = lerp_angle(current_rot, target_rot, delta * 5.0)
				
		elif enemy_in_range and current_enemy and is_instance_valid(current_enemy):
			# COMBAT MODE: Only rotate to face enemy, but maintain formation position
			var direction_to_enemy = current_enemy.global_transform.origin - clone.global_transform.origin
			direction_to_enemy.y = 0
			
			if direction_to_enemy.length() > 0.1:
				var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
				clone.rotation.y = lerp_angle(clone.rotation.y, target_rotation, delta * 5.0)
				
				# Keep in combat stance while enemy in range
				if clone_anim_player and clone_anim_player.current_animation != "Aim" and clone_anim_player.current_animation != "Fire":
					clone_anim_player.play("Aim")
			
			# CRITICAL: Continue with normal formation positioning, but don't adjust rotations
			# This way clones will maintain formation position but still face enemies
			
			# Dead zone to stop jitter - applied during combat too
			if distance < 0.05:
				var pos = clone.global_transform.origin
				pos.y = global_transform.origin.y + 0.001
				clone.global_transform.origin = pos
				continue
				
			# Move toward formation position while still facing enemy
			clone.global_translate(move_vec.normalized() * stats.move_speed * 0.5 * delta)
		else:
			# Return to idle if not moving and not in combat
			if clone_anim_player and clone_anim_player.current_animation != "Idle_1":
				clone_anim_player.play("Idle_1")
		
		# Dead zone to stop jitter - ONLY apply this when not in combat
		if distance < 0.05 and not enemy_in_range:
			var pos = clone.global_transform.origin
			pos.y = global_transform.origin.y + 0.001
			clone.global_transform.origin = pos

			# Only switch to idle if not moving and we're not in combat
			if clone_anim_player and clone_anim_player.current_animation != "Idle_1" and not is_attacking and not is_moving:
				clone_anim_player.play("Idle_1")
			continue

		# ⛔ Avoid getting too close to the leader
		var to_leader = clone.global_transform.origin - global_transform.origin
		to_leader.y = 0
		var dist_to_leader = to_leader.length()
		if dist_to_leader < 1.5:
			var push_away = to_leader.normalized() * (1.5 - dist_to_leader)
			clone.global_translate(push_away * delta * 4.0)  # strong push

		# ⛔ Avoid other clones
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

		# Set correct height
		var new_pos = clone.global_transform.origin
		new_pos.y = global_transform.origin.y + 0.1
		clone.global_transform.origin = new_pos

func move_to_position(pos: Vector3):
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
	
	# Use the vision_range from stats instead of hardcoded 20.0
	var detection_range = stats.vision_range if stats and stats.get("vision_range") != null else 20.0

	for node in get_tree().get_nodes_in_group(opposing_group):
		if not node is CharacterBody3D or not is_instance_valid(node):
			continue
		var dist = global_transform.origin.distance_to(node.global_transform.origin)
		if dist <= detection_range and dist < closest_distance:
			closest_enemy = node
			closest_distance = dist

	if closest_enemy:
		if not enemy_in_range or current_enemy != closest_enemy:
			enemy_in_range = true
			current_enemy = closest_enemy
			
			# Begin aiming immediately upon detecting enemy
			if anim_player and anim_player.has_animation("Aim"):
				anim_player.play("Aim")
				
			# Make clones aim immediately too
			for clone in infantry_clones.duplicate():  # Use duplicate to avoid modification during iteration
				if is_instance_valid(clone) and not clone.is_queued_for_deletion():
					_clone_play_animation(clone, "Aim")
	elif enemy_in_range:
		enemy_in_range = false
		current_enemy = null
		
		# Return to idle when no enemies are in range
		if anim_player:
			anim_player.play("Idle_1")
			
		for clone in infantry_clones.duplicate():  # Use duplicate to avoid modification during iteration
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				_clone_play_animation(clone, "Idle_1")

func _perform_attack():
	if not current_enemy or not is_instance_valid(current_enemy):
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

	is_attacking = true

	# Aim anims
	if anim_player and anim_player.has_animation("Aim"):
		anim_player.play("Aim")

	# Make a safe copy of the clones array to avoid modification during iteration
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			valid_clones.append(clone)
			_clone_play_animation(clone, "Aim")

	await get_tree().create_timer(0.3).timeout

	# Fire anims
	if anim_player and anim_player.has_animation("Fire") and is_instance_valid(current_enemy):
		anim_player.play("Fire")

	# Get squad strength for damage calculation based on valid clones
	var squad_strength = 1 + valid_clones.size()

	for i in range(valid_clones.size()):
		var clone = valid_clones[i]
		if not is_instance_valid(clone) or clone.is_queued_for_deletion():
			continue
			
		var stagger_time = 0.05 * (i % 3)
		if stagger_time > 0:
			await get_tree().create_timer(stagger_time).timeout
		_clone_play_animation(clone, "Fire")

	# Combat logic only performed by leader
	if current_enemy and is_instance_valid(current_enemy):
		var distance = global_transform.origin.distance_to(current_enemy.global_transform.origin)
		var accuracy = 0.0
		if distance <= 10.0:
			accuracy = stats.short_range_accuracy
		elif distance <= 20.0:
			accuracy = stats.medium_range_accuracy
		else:
			accuracy = stats.long_range_accuracy

		# Calculate hits based on squad strength and accuracy
		var total_hits = 0
		for i in range(squad_strength):
			if randf() <= accuracy:
				total_hits += 1
				
		if total_hits > 0 and current_enemy.has_method("take_damage"):
			current_enemy.take_damage(total_hits)

	await get_tree().create_timer(0.5).timeout  # Give time for anims to finish
	
	# Make sure we're still in combat stance after attack finishes
	if is_instance_valid(current_enemy) and enemy_in_range:
		if anim_player and anim_player.has_animation("Aim"):
			anim_player.play("Aim")
			
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				_clone_play_animation(clone, "Aim")
	
	is_attacking = false

func take_damage(amount: int):
	# Distribute damage among clones first
	var remaining_damage = amount
	var clones_to_remove = []
	
	# Make a safe copy to iterate through
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			valid_clones.append(clone)
	
	# Randomly distribute damage among squad members
	while remaining_damage > 0 and (valid_clones.size() > 0 or stats.health > 0):
		# Randomly choose between leader and clones
		var target_leader = randf() < (1.0 / (valid_clones.size() + 1))
		
		if target_leader or valid_clones.size() == 0:
			# Damage goes to the leader
			stats.health -= 1
			remaining_damage -= 1
			
			if stats.health <= 0:
				# Leader is dead, whole squad is destroyed
				_destroy_squad()
				return
		else:
			# Damage goes to a random clone
			var target_index = randi() % valid_clones.size()
			var clone = valid_clones[target_index]
			var hp = clone.get_meta("health")
			hp -= 1
			remaining_damage -= 1
			
			if hp <= 0:
				clones_to_remove.append(clone)
				# Remove from valid_clones to avoid targeting dead units
				valid_clones.erase(clone)
			else:
				clone.set_meta("health", hp)
	
	# Remove dead clones
	for clone in clones_to_remove:
		infantry_clones.erase(clone)
		clone.queue_free()
	
	# Final check - if leader health is <= 0 or if there are no clones left and leader health is critical,
	# destroy the entire squad
	if stats.health <= 0 or (valid_clones.size() == 0 and stats.health <= 1):
		_destroy_squad()

# New method to properly handle squad destruction
func _destroy_squad():
	# First, clean up all clones
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			clone.queue_free()
	
	# Clear the clones array
	infantry_clones.clear()
	
	# Make sure we're no longer a target for enemy units
	# Remove from combat groups
	if is_in_group("allies"):
		remove_from_group("allies")
	if is_in_group("axis"):
		remove_from_group("axis")
	
	# Clear current enemy reference
	current_enemy = null
	enemy_in_range = false
	
	# Set up a small delay before we remove ourselves
	# This allows any ongoing effects/sounds to finish
	var timer = get_tree().create_timer(0.1)
	await timer.timeout
	
	# Finally, queue ourselves for deletion
	queue_free()
