extends CharacterBody3D
class_name SquadUnit

signal unit_died(unit: SquadUnit)
signal unit_selected(unit: SquadUnit)
signal unit_deselected(unit: SquadUnit)
signal leader_changed(new_leader: Node3D)

@export var stats: CombatUnitData

@onready var infantry_template: Node3D = $Infantry
@onready var nav_agent: NavigationAgent3D = $Infantry/NavigationAgent3D
@onready var selection_ring: Node3D = $Infantry/SelectionRing
@onready var unit_bar: Node3D = $UnitBar
@onready var animation_manager: SquadAnimationManager

var current_enemy: Node = null
var attack_timer: float = 0.0
var attack_interval: float = 2.0
var clone_targets: Dictionary = {}
var clone_attack_timers: Dictionary = {}

# HEALTH SYSTEM
var squad_size: int
var alive_members: int
var current_health: int
var max_health: int
var is_dead: bool = false
var clone_max_health: int = 100
var leader_max_health: int = 100

# LEADERSHIP SYSTEM
var current_leader: Node3D
var original_leader: Node3D
var leader_is_original: bool = true
var leadership_succession_enabled: bool = true

# COMPATIBILITY PROPERTIES
var health: int:
	get: return current_health
var total_health: int:
	get: return current_health

var squad_id: String
var clones: Array[Node3D] = []
var cache_dirty: bool = true

var _is_selected: bool = false
var is_selected: bool:
	get: return _is_selected
	set(value): _set_selection(value)

func _set_selection(value: bool):
	if is_dead: return
	if _is_selected == value: return
	_is_selected = value
	
	# Single point of selection visual update
	_update_all_selection_visuals()
	
	if value:
		unit_selected.emit(self)
	else:
		unit_deselected.emit(self)

func set_selected(value: bool) -> void:
	is_selected = value

func _ready():
	_initialize_squad()
	_setup_navigation()
	_connect_signals()
	_setup_animation_manager()

func _setup_animation_manager():
	"""Initialize the centralized animation manager"""
	# Create the animation manager
	animation_manager = SquadAnimationManager.new()
	animation_manager.name = "AnimationManager"
	animation_manager.squad_unit = self
	add_child(animation_manager)
	
	print("Created centralized animation manager for squad: ", squad_id)

func _initialize_squad():
	squad_id = "Squad_" + str(get_instance_id())
	original_leader = self
	current_leader = self
	leader_is_original = true
	
	var default_health = 100
	var default_interval = 4.0
	
	if stats:
		leader_max_health = stats.health
		clone_max_health = stats.health
		attack_interval = stats.attack_interval  # This is now properly used
		squad_size = stats.squad_size
		_spawn_clones(stats.squad_size - 1)
		print("DEBUG: Attack interval loaded from stats: ", stats.attack_interval)
	else:
		leader_max_health = default_health
		clone_max_health = default_health
		attack_interval = default_interval
		squad_size = 1
		print("DEBUG: Using default attack interval: ", default_interval)
	
	print("DEBUG: Final attack_interval value: ", attack_interval)
	
	alive_members = squad_size
	max_health = leader_max_health + (squad_size - 1) * clone_max_health
	current_health = max_health
	
	_initialize_unit_metadata(self, leader_max_health, true)
	
	for clone in clones:
		_initialize_unit_metadata(clone, clone_max_health, false)
	
	_setup_ui()
	_update_health_bar()

func _initialize_unit_metadata(unit: Node3D, health: int, is_leader: bool):
	"""Initialize metadata for a unit (leader or clone)"""
	unit.set_meta("health", health)
	unit.set_meta("max_health", health)
	unit.set_meta("is_dead", false)
	unit.set_meta("is_leader", is_leader)
	unit.set_meta("squad_reference", self)
	if unit != self:
		unit.set_meta("can_be_promoted", true)
		unit.set_meta("clone_index", clones.size())

func _spawn_clones(count: int):
	var container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if not container:
		push_error("CloneContainer not found in scene")
		return
	
	for i in range(count):
		var clone = await _create_clone(i, count, container)
		if clone: 
			clones.append(clone)
			clone.add_to_group("squad_clones")
			clone.add_to_group("infantry")
	cache_dirty = true

func _create_clone(index: int, total_count: int, container: Node) -> Node3D:
	var clone = infantry_template.duplicate()
	clone.name = "Clone_%s_%d" % [squad_id, index]
	
	var spacing = stats.formation_spacing if stats else 3.0
	var angle = (index * TAU) / total_count
	var offset = Vector3(sin(angle) * spacing, 0, cos(angle) * spacing)
	clone.set_meta("formation_offset", offset)
	clone.set_meta("squad_id", squad_id)
	
	container.add_child(clone)
	clone.global_transform.origin = global_transform.origin + offset
	_setup_clone_components(clone)
	
	# Register clone with animation manager
	if animation_manager:
		# Wait a frame for clone to be fully set up
		await get_tree().process_frame
		animation_manager.register_new_unit(clone)
	
	return clone

func _setup_clone_components(clone: Node3D):
	var clone_nav = clone.get_node_or_null("NavigationAgent3D")
	if not clone_nav:
		clone_nav = NavigationAgent3D.new()
		clone_nav.path_desired_distance = 0.5
		clone_nav.target_desired_distance = 0.5
		clone.add_child(clone_nav)
	
	var ring = clone.get_node_or_null("SelectionRing")
	if ring: ring.visible = false

func _setup_navigation():
	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5

func _setup_ui():
	if selection_ring: selection_ring.visible = false
	if unit_bar:
		unit_bar.squad_owner = self
		if stats and stats.unit_icon:
			unit_bar.set_albedo_texture(stats.unit_icon)
		
		# Attach unit bar to original leader initially
		_attach_unit_bar_to_unit(self)

func _connect_signals():
	if nav_agent: nav_agent.navigation_finished.connect(_on_navigation_finished)

# SELECTION SYSTEM
func _update_all_selection_visuals():
	"""Centralized selection visual update - show rings on all living units when selected"""
	# Hide all rings first
	_hide_all_selection_rings()
	
	# Show rings on all living units if squad is selected
	if _is_selected:
		# Show ring on current leader
		if current_leader and is_instance_valid(current_leader) and not current_leader.get_meta("is_dead", false):
			var leader_ring = _get_selection_ring_for_unit(current_leader)
			if leader_ring:
				leader_ring.visible = true
		
		# Show rings on all living clones
		for clone in clones:
			if _is_clone_alive(clone):
				var clone_ring = _get_selection_ring_for_unit(clone)
				if clone_ring:
					clone_ring.visible = true

func _hide_all_selection_rings():
	"""Hide selection rings on all units"""
	# Hide ring on original leader
	if selection_ring:
		selection_ring.visible = false
	
	# Hide rings on all clones
	for clone in clones:
		if is_instance_valid(clone):
			var ring = clone.get_node_or_null("SelectionRing")
			if ring:
				ring.visible = false

func _get_selection_ring_for_unit(unit: Node3D) -> Node3D:
	"""Get the selection ring for any unit (leader or clone)"""
	if unit == original_leader:
		return selection_ring
	else:
		return unit.get_node_or_null("SelectionRing")

func _update_selection_visuals():
	"""Legacy method - redirect to new centralized system"""
	if _is_selected:
		_update_all_selection_visuals()

# LEADERSHIP SYSTEM
func _get_navigation_agent(unit: Node3D) -> NavigationAgent3D:
	"""Get NavigationAgent3D from a unit"""
	if unit == original_leader:
		return nav_agent
	else:
		return unit.get_node_or_null("NavigationAgent3D")

func _attach_unit_bar_to_unit(unit: Node3D):
	"""Attach unit bar to a specific unit"""
	if not unit_bar: return
	
	var current_parent = unit_bar.get_parent()
	if current_parent and current_parent != unit:
		current_parent.remove_child(unit_bar)
	
	if unit_bar.get_parent() != unit:
		unit.add_child(unit_bar)
		unit_bar.position = Vector3(0, 3, 0)

func _update_unit_bar_position():
	"""Update unit bar position to follow current leader"""
	if not unit_bar or not current_leader: return
	var target_position = current_leader.global_position + Vector3(0, 6, 0)
	unit_bar.global_position = target_position

func _promote_clone_to_leader():
	"""Promote first available living clone to squad leader"""
	if not leadership_succession_enabled:
		return false
	
	var new_leader_clone = null
	for clone in clones:
		if _is_clone_alive(clone) and clone.get_meta("can_be_promoted", true):
			new_leader_clone = clone
			break
	
	if not new_leader_clone:
		return false
	
	print("Promoting clone ", new_leader_clone.name, " to squad leader")
	
	# Update leadership
	var old_leader = current_leader
	current_leader = new_leader_clone
	leader_is_original = false
	
	# Update metadata
	if old_leader and is_instance_valid(old_leader):
		old_leader.set_meta("is_leader", false)
	new_leader_clone.set_meta("is_leader", true)
	
	# Transfer responsibilities
	_transfer_leadership_responsibilities(old_leader, new_leader_clone)
	_attach_unit_bar_to_unit(new_leader_clone)
	_update_leader_visuals(new_leader_clone)
	
	# Update selection visuals for new leader
	if _is_selected:
		_update_all_selection_visuals()
	
	leader_changed.emit(new_leader_clone)
	return true

func _transfer_leadership_responsibilities(old_leader: Node3D, new_leader: Node3D):
	"""Transfer navigation from old to new leader"""
	if old_leader and is_instance_valid(old_leader):
		var old_nav = _get_navigation_agent(old_leader)
		if old_nav and not old_nav.is_navigation_finished():
			var target_pos = old_nav.get_target_position()
			var new_nav = _get_navigation_agent(new_leader)
			if new_nav:
				new_nav.set_target_position(target_pos)
	
	if leader_is_original and old_leader == original_leader:
		nav_agent = _get_navigation_agent(new_leader)

func _update_leader_visuals(new_leader: Node3D):
	"""Update visual indicators for new leader"""
	if new_leader != original_leader:
		new_leader.scale = Vector3(1.1, 1.1, 1.1)
	
	for clone in clones:
		if clone != new_leader and clone.get_meta("is_leader", false):
			clone.scale = Vector3(1.0, 1.0, 1.0)
			clone.set_meta("is_leader", false)

# DAMAGE SYSTEM
func handle_clone_damage(clone: Node3D, damage_amount: int):
	"""Handle damage to a clone"""
	if not is_instance_valid(clone) or clone.get_meta("is_dead", false):
		return
	
	var current_clone_health = clone.get_meta("health", 0)
	current_clone_health = max(0, current_clone_health - damage_amount)
	clone.set_meta("health", current_clone_health)
	
	_recalculate_squad_health()
	_update_health_bar()
	
	if current_clone_health <= 0:
		_kill_unit_immediately(clone)

func take_damage(amount: int):
	"""Original leader takes damage"""
	if is_dead or get_meta("is_dead", false): return
	
	var leader_health = get_meta("health", leader_max_health)
	leader_health = max(0, leader_health - amount)
	set_meta("health", leader_health)
	
	if leader_health <= 0:
		set_meta("is_dead", true)
		alive_members = max(0, alive_members - 1)
		
		# Notify animation manager that leader died
		if animation_manager:
			animation_manager.mark_unit_dead(self)
		
		if current_leader == original_leader:
			if not _promote_clone_to_leader():
				current_leader = null
		
		_set_node_visibility_and_collision(self, false)
	
	_recalculate_squad_health()
	_update_health_bar()
	
	if alive_members <= 0:
		_die()

func _kill_unit_immediately(unit: Node3D):
	"""Kill a unit immediately and handle succession"""
	if unit.get_meta("is_dead", false):
		return
	
	var was_leader = unit.get_meta("is_leader", false)
	unit.set_meta("is_dead", true)
	unit.set_meta("health", 0)
	alive_members = max(0, alive_members - 1)
	cache_dirty = true
	
	print("Killing unit immediately: ", unit.name, " (was leader: ", was_leader, ")")
	
	# Notify animation manager that unit died
	if animation_manager:
		animation_manager.mark_unit_dead(unit)
	
	# Clean up targeting - remove this unit as a target for everyone
	_remove_unit_as_target(unit)
	
	# Clean up this unit's own targets
	clone_targets.erase(unit)
	clone_attack_timers.erase(unit.get_instance_id())
	
	# Handle leadership succession
	if was_leader and unit == current_leader:
		print("Current leader died, attempting succession...")
		if not _promote_clone_to_leader():
			if not original_leader.get_meta("is_dead", false):
				print("Reverting to original leader")
				current_leader = original_leader
				leader_is_original = true
				_attach_unit_bar_to_unit(original_leader)
			else:
				print("No valid leader remaining")
				current_leader = null
	
	# Clean up unit
	_set_unit_visibility_and_collision(unit, false)
	_recalculate_squad_health()
	_update_health_bar()
	
	# Update selection visuals after unit death
	if _is_selected:
		_update_all_selection_visuals()
	
	if alive_members <= 0:
		_die()

func _remove_unit_as_target(dead_unit: Node3D):
	"""Remove a dead unit as a target from all other squads"""
	# Clear from our own targeting
	if current_enemy == dead_unit:
		current_enemy = null
		print("Cleared dead unit as main enemy target")
	
	# Clear from clone targets
	var clones_to_clear = []
	for clone in clone_targets.keys():
		if clone_targets[clone] == dead_unit:
			clones_to_clear.append(clone)
	
	for clone in clones_to_clear:
		clone_targets.erase(clone)
		clone_attack_timers.erase(clone.get_instance_id())
		print("Cleared dead unit as clone target for ", clone.name)
	
	# Notify other squads to clear this unit as their target
	var all_squads = get_tree().get_nodes_in_group("allies") + get_tree().get_nodes_in_group("axis")
	for squad in all_squads:
		if squad != self and squad.has_method("_clear_dead_target"):
			squad._clear_dead_target(dead_unit)

func _clear_dead_target(dead_unit: Node3D):
	"""Called by other squads to clear a dead unit as target"""
	if current_enemy == dead_unit:
		current_enemy = null
	
	var clones_to_clear = []
	for clone in clone_targets.keys():
		if clone_targets[clone] == dead_unit:
			clones_to_clear.append(clone)
	
	for clone in clones_to_clear:
		clone_targets.erase(clone)
		clone_attack_timers.erase(clone.get_instance_id())

func _recalculate_squad_health():
	"""Recalculate total squad health"""
	var total_health = 0
	
	if not original_leader.get_meta("is_dead", false):
		total_health += original_leader.get_meta("health", 0)
	
	for clone in clones:
		if is_instance_valid(clone) and not clone.get_meta("is_dead", false):
			total_health += clone.get_meta("health", 0)
	
	current_health = total_health

# MOVEMENT SYSTEM
func _physics_process(delta: float) -> void:
	if is_dead: return
	if alive_members <= 0 or current_health <= 0:
		_die()
		return
	
	_update_movement(delta)
	_update_combat(delta)
	_update_unit_bar_position()

func _update_movement(delta: float):
	if current_leader and is_instance_valid(current_leader):
		_move_leader(delta)
	
	for clone in clones:
		if _is_clone_alive(clone) and clone != current_leader:
			_move_single_clone(clone, delta)

func _move_leader(delta: float):
	"""Move current leader"""
	var leader_nav = _get_navigation_agent(current_leader)
	
	if not leader_nav or leader_nav.is_navigation_finished():
		if current_leader == original_leader:
			velocity = Vector3.ZERO
			move_and_slide()
		return
	
	var next_pos = leader_nav.get_next_path_position()
	var direction = (next_pos - current_leader.global_transform.origin).normalized()
	
	if direction.length() > 0.1:
		_rotate_unit(current_leader, direction, delta, 8.0)
	
	var move_speed = stats.move_speed if stats else 5.0
	
	if current_leader == original_leader:
		velocity = direction * move_speed
		move_and_slide()
	else:
		current_leader.global_translate(direction * move_speed * delta)

func _move_single_clone(clone: Node3D, delta: float):
	var clone_nav := clone.get_node_or_null("NavigationAgent3D")
	if not clone_nav: return

	var leader_pos = current_leader.global_transform.origin if current_leader else global_transform.origin
	var offset = clone.get_meta("formation_offset", Vector3.ZERO)
	var formation_target = leader_pos + offset
	var separation_force = _calculate_separation_force(clone)
	var adjusted_target = formation_target + separation_force
	
	clone_nav.set_target_position(adjusted_target)

	if not clone_nav.is_navigation_finished():
		var next_pos = clone_nav.get_next_path_position()
		var direction = (next_pos - clone.global_transform.origin).normalized()
		var move_speed = stats.move_speed if stats else 5.0
		clone.global_translate(direction * move_speed * delta)
		_rotate_unit(clone, direction, delta, 4.0)

func _calculate_separation_force(clone: Node3D) -> Vector3:
	var separation_force := Vector3.ZERO
	var separation_distance = 2.5
	
	if current_leader and is_instance_valid(current_leader):
		var to_leader = clone.global_transform.origin - current_leader.global_transform.origin
		var leader_dist = to_leader.length()
		if leader_dist > 0 and leader_dist < separation_distance:
			separation_force += to_leader.normalized() * (separation_distance - leader_dist)
	
	for other in clones:
		if other == clone or not _is_clone_alive(other): continue
		var to_other = clone.global_transform.origin - other.global_transform.origin
		var dist = to_other.length()
		if dist > 0 and dist < separation_distance:
			separation_force += to_other.normalized() * (separation_distance - dist)
	
	return separation_force

func _rotate_unit(unit: Node3D, direction: Vector3, delta: float, speed: float):
	unit.rotation.y = lerp_angle(unit.rotation.y, atan2(direction.x, direction.z), delta * speed)

func move_to_position(pos: Vector3):
	if not is_dead and current_leader and is_instance_valid(current_leader):
		var leader_nav = _get_navigation_agent(current_leader)
		if leader_nav:
			leader_nav.set_target_position(pos)

# COMBAT SYSTEM - FIXED ATTACK TIMING
# COMBAT SYSTEM - CONFIGURABLE STAGGERED ATTACKS
func _update_combat(delta: float):
	_validate_current_targets()
	_find_enemies()
	_face_target_when_possible(delta)
	_attack_staggered(delta)

func _attack_staggered(delta: float):
	"""Configurable staggered attack system that uses CombatUnitData settings"""
	if not current_enemy or not is_instance_valid(current_enemy) or not current_leader: 
		return
	
	var leader_nav = _get_navigation_agent(current_leader)
	var can_attack = not leader_nav or leader_nav.is_navigation_finished() or (current_leader == original_leader and velocity.length() < 0.1)
	if not can_attack: 
		return
		
	attack_timer += delta
	
	# Leader attacks with configurable delay
	var leader_attack_delay = stats.leader_delay if stats else 0.0
	if attack_timer >= attack_interval + leader_attack_delay:
		attack_timer = 0.0
		_perform_leader_attack()
		_schedule_clone_attacks()

func _perform_leader_attack():
	"""Leader attacks with configurable timing"""
	if current_enemy and is_instance_valid(current_enemy) and current_leader and is_instance_valid(current_leader):
		var distance = current_leader.global_transform.origin.distance_to(current_enemy.global_transform.origin)
		var attack_range = stats.attack_range if stats else 20.0
		if distance <= attack_range:
			_fire_shot_at_target(current_leader, current_enemy, distance)
			
			# Notify animation manager that leader is firing NOW
			if animation_manager:
				animation_manager.trigger_unit_fire_animation(current_leader)
			
			print("Leader ", current_leader.name, " fired at ", current_enemy.name)

func _schedule_clone_attacks():
	"""Schedule clone attacks with configurable staggering from CombatUnitData"""
	var valid_clones = []
	
	# Collect all clones that can attack
	for clone in clones:
		if not _is_clone_alive(clone): continue
		var clone_target = clone_targets.get(clone, null)
		if not clone_target or not is_instance_valid(clone_target): continue
		
		var clone_nav = clone.get_node_or_null("NavigationAgent3D")
		var can_attack = not clone_nav or clone_nav.is_navigation_finished()
		if not can_attack: continue
		
		var distance = clone.global_transform.origin.distance_to(clone_target.global_transform.origin)
		var attack_range = stats.attack_range if stats else 20.0
		if distance <= attack_range:
			valid_clones.append(clone)
	
	# Get stagger settings from CombatUnitData (with fallbacks)
	var initial_delay = stats.clone_initial_delay if stats else 0.3
	var stagger_interval = stats.clone_stagger_interval if stats else 0.4
	var randomization = stats.stagger_randomization if stats else 0.1
	
	# Schedule staggered attacks for valid clones
	for i in range(valid_clones.size()):
		var clone = valid_clones[i]
		
		# Calculate delay: initial delay + (clone index * stagger interval) + random variation
		var base_delay = initial_delay + (i * stagger_interval)
		var random_offset = randf_range(-randomization, randomization)
		var final_delay = max(0.0, base_delay + random_offset)
		
		# Schedule the attack
		get_tree().create_timer(final_delay).timeout.connect(_execute_clone_attack.bind(clone))
		
		print("Scheduled clone ", i, " (", clone.name, ") to fire in ", final_delay, " seconds")

func _execute_clone_attack(clone: Node3D):
	"""Execute a scheduled clone attack"""
	if not _is_clone_alive(clone): return
	
	var clone_target = clone_targets.get(clone, null)
	if not clone_target or not is_instance_valid(clone_target): return
	
	var distance = clone.global_transform.origin.distance_to(clone_target.global_transform.origin)
	var attack_range = stats.attack_range if stats else 20.0
	if distance > attack_range: return
	
	_fire_shot_at_target(clone, clone_target, distance)
	
	# Notify animation manager that this clone is firing NOW
	if animation_manager:
		animation_manager.trigger_unit_fire_animation(clone)
	
	print("Clone ", clone.name, " fired at ", clone_target.name, " (staggered)")

# Helper method to get current stagger settings for debugging
func get_stagger_settings() -> Dictionary:
	"""Debug method to see current stagger settings"""
	if not stats:
		return {
			"leader_delay": 0.0,
			"clone_initial_delay": 0.3,
			"clone_stagger_interval": 0.4,
			"stagger_randomization": 0.1,
			"source": "defaults"
		}
	
	return {
		"leader_delay": stats.leader_delay,
		"clone_initial_delay": stats.clone_initial_delay,
		"clone_stagger_interval": stats.clone_stagger_interval,
		"stagger_randomization": stats.stagger_randomization,
		"source": "CombatUnitData"
	}

func _validate_current_targets():
	"""Comprehensive target validation and cleanup"""
	# Validate main enemy
	if current_enemy and not _is_enemy_truly_valid(current_enemy):
		current_enemy = null
	
	# Validate clone targets
	var targets_to_remove = []
	for clone in clone_targets.keys():
		if not _is_clone_alive(clone):
			# Clone is dead, remove its target
			targets_to_remove.append(clone)
			continue
			
		var target = clone_targets[clone]
		if not _is_enemy_truly_valid(target):
			targets_to_remove.append(clone)
	
	# Clean up invalid targets
	for clone in targets_to_remove:
		clone_targets.erase(clone)
		if clone and is_instance_valid(clone):
			clone_attack_timers.erase(clone.get_instance_id())

func _is_enemy_truly_valid(enemy: Node) -> bool:
	"""Comprehensive enemy validation"""
	if not enemy or not is_instance_valid(enemy):
		return false
	
	# Check if enemy is marked as dead
	if enemy.has_meta("is_dead") and enemy.get_meta("is_dead"):
		return false
	
	# Check if enemy has is_dead method and is dead
	if enemy.has_method("is_dead") and enemy.is_dead():
		return false
	
	# For SquadUnit enemies, check if they're actually dead
	if enemy is SquadUnit:
		if enemy.is_dead or enemy.alive_members <= 0 or enemy.current_health <= 0:
			return false
	
	# Check if enemy has health and is at 0
	if enemy.has_meta("health") and enemy.get_meta("health", 1) <= 0:
		return false
	
	# Check collision - disabled collision usually means dead/inactive
	var collision = enemy.get_node_or_null("CollisionShape3D")
	if collision and collision.disabled:
		return false
	
	# Check if enemy is still in appropriate groups
	var enemy_groups = ["allies", "axis", "infantry"]
	var found_group = false
	for group in enemy_groups:
		if enemy.is_in_group(group):
			found_group = true
			break
	
	if not found_group:
		return false
	
	return true

func _find_enemies():
	if not current_leader or not is_instance_valid(current_leader):
		return
	
	var opposing_group = "allies" if is_in_group("axis") else "axis"
	var potential_enemies = get_tree().get_nodes_in_group(opposing_group)
	
	# Add enemy clones
	var clone_container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if clone_container:
		for child in clone_container.get_children():
			if child.has_meta("squad_id") and not child.get_meta("is_dead", false):
				var clone_squad_id = child.get_meta("squad_id", "")
				for enemy_squad in potential_enemies:
					if enemy_squad is SquadUnit and enemy_squad.squad_id == clone_squad_id:
						potential_enemies.append(child)
						break
	
	var already_assigned = []
	
	# Assign targets
	current_enemy = _get_closest_available_enemy(potential_enemies, current_leader.global_transform.origin, already_assigned)
	if current_enemy:
		already_assigned.append(current_enemy)
	
	for clone in clones:
		if _is_clone_alive(clone):
			var clone_target = _get_closest_available_enemy(potential_enemies, clone.global_transform.origin, already_assigned)
			if not clone_target:
				clone_target = _get_closest_available_enemy(potential_enemies, clone.global_transform.origin, [])
			
			if clone_target:
				clone_targets[clone] = clone_target
				already_assigned.append(clone_target)
			else:
				clone_targets.erase(clone)

func _get_closest_available_enemy(enemies: Array, from_position: Vector3, already_assigned: Array) -> Node:
	var closest_enemy: Node = null
	var closest_distance = INF
	var max_range = stats.attack_range if stats else 20.0
	
	for enemy in enemies:
		if not _is_enemy_truly_valid(enemy) or enemy in already_assigned: continue
		var distance = from_position.distance_to(enemy.global_transform.origin)
		if distance <= max_range and distance < closest_distance:
			closest_enemy = enemy
			closest_distance = distance
	return closest_enemy

func _face_target_when_possible(delta: float):
	if not current_enemy or not is_instance_valid(current_enemy) or not current_leader: return
	
	var leader_nav = _get_navigation_agent(current_leader)
	var should_face_target = not leader_nav or leader_nav.is_navigation_finished()
	
	if should_face_target:
		var direction_to_enemy = (current_enemy.global_transform.origin - current_leader.global_transform.origin).normalized()
		_rotate_unit(current_leader, direction_to_enemy, delta, 6.0)
		_make_clones_face_target(delta)

func _make_clones_face_target(delta: float):
	for clone in clones:
		if not _is_clone_alive(clone): continue
		
		var clone_target = clone_targets.get(clone, null)
		if not clone_target or not is_instance_valid(clone_target): continue
		
		var clone_nav = clone.get_node_or_null("NavigationAgent3D")
		var should_face = _should_clone_face_target(clone, clone_nav)
		
		if should_face:
			var direction_to_enemy = (clone_target.global_transform.origin - clone.global_transform.origin).normalized()
			_rotate_unit(clone, direction_to_enemy, delta, 5.0)

func _should_clone_face_target(clone: Node3D, clone_nav: NavigationAgent3D) -> bool:
	if not clone_nav: return false
	if clone_nav.is_navigation_finished(): return true
	
	var leader_pos = current_leader.global_transform.origin if current_leader else global_transform.origin
	var offset = clone.get_meta("formation_offset", Vector3.ZERO)
	var formation_target = leader_pos + offset
	return clone.global_transform.origin.distance_to(formation_target) < 1.0

func _fire_shot_at_target(shooter: Node3D, target: Node, distance: float):
	if not target or not is_instance_valid(target) or is_dead: return
	
	var muzzle_flash_script = _find_muzzle_flash_script(shooter)
	if muzzle_flash_script:
		muzzle_flash_script.fire_at_target(target, distance, shooter.global_transform.origin)

func _find_muzzle_flash_script(unit: Node3D) -> Node:
	for child in unit.get_children():
		if child.name == "MuzzleFlash" or child.has_method("fire_at_target"):
			return child
		var found = _find_muzzle_flash_script_recursive(child)
		if found:
			return found
	return null

func _find_muzzle_flash_script_recursive(node: Node) -> Node:
	if node.has_method("fire_at_target"):
		return node
	for child in node.get_children():
		var found = _find_muzzle_flash_script_recursive(child)
		if found:
			return found
	return null

# UTILITY FUNCTIONS
func get_health_percentage() -> float:
	if max_health == 0: return 0.0
	return float(current_health) / float(max_health)

func _update_health_bar():
	if is_instance_valid(unit_bar) and unit_bar.has_method("set_health_bar"):
		var health_percent = get_health_percentage()
		unit_bar.set_health_bar(health_percent)

func _is_clone_alive(clone: Node3D) -> bool:
	return is_instance_valid(clone) and not clone.get_meta("is_dead", false)

func _set_node_visibility_and_collision(node: Node3D, enabled: bool):
	if not enabled:
		# Delete collision shapes instead of just disabling
		_delete_all_collision_shapes(node)
	else:
		# Ensure collision shapes are enabled (if they exist)
		_enable_collision_shapes(node)

func _set_unit_visibility_and_collision(unit: Node3D, enabled: bool):
	"""Set visibility and collision for a unit (works for both leader and clones)"""
	if not enabled:
		# Unit is dying - delete all collision shapes
		_delete_all_collision_shapes(unit)
		_clean_up_dead_unit_components(unit)
	else:
		# Unit is alive - ensure collision shapes are enabled (if they exist)
		_enable_collision_shapes(unit)

func _delete_all_collision_shapes(unit: Node3D):
	"""Recursively find and delete all CollisionShape3D nodes in a unit"""
	_delete_collision_shapes_recursive(unit)
	print("Deleted all collision shapes for dead unit: ", unit.name)

func _delete_collision_shapes_recursive(node: Node):
	"""Recursively delete collision shapes in node and all children"""
	var children_to_process = []
	
	# Collect children first to avoid modifying tree while iterating
	for child in node.get_children():
		children_to_process.append(child)
	
	# Process each child
	for child in children_to_process:
		if child is CollisionShape3D:
			print("Deleting CollisionShape3D: ", child.name, " from ", node.name)
			child.queue_free()
		else:
			# Recursively check children
			_delete_collision_shapes_recursive(child)

func _enable_collision_shapes(unit: Node3D):
	"""Enable all collision shapes for a living unit"""
	_enable_collision_shapes_recursive(unit)

func _enable_collision_shapes_recursive(node: Node):
	"""Recursively enable collision shapes in node and all children"""
	for child in node.get_children():
		if child is CollisionShape3D:
			child.disabled = false
		else:
			_enable_collision_shapes_recursive(child)

func _clean_up_dead_unit_components(unit: Node3D):
	"""Remove components that could cause targeting issues, but keep visual elements"""
	
	# Remove from groups so they can't be targeted
	unit.remove_from_group("infantry")
	unit.remove_from_group("squad_clones")
	
	# Disable navigation agent
	var nav_agent = unit.get_node_or_null("NavigationAgent3D")
	if nav_agent:
		nav_agent.set_process_mode(Node.PROCESS_MODE_DISABLED)
	
	# Hide selection ring
	var ring = _get_selection_ring_for_unit(unit)
	if ring:
		ring.visible = false
	
	# Disable any area or collision detection nodes (but don't delete them)
	for child in unit.get_children():
		if child is Area3D or child is RigidBody3D:
			child.set_deferred("monitoring", false)
			child.set_deferred("monitorable", false)
	
	print("Cleaned up components for dead unit: ", unit.name)

func _die():
	if is_dead: return
	is_dead = true
	current_health = 0
	alive_members = 0
	set_selected(false)
	_set_node_visibility_and_collision(self, false)
	if selection_ring: selection_ring.visible = false
	if unit_bar: unit_bar.delete_unit_bar()
	
	# Mark all remaining units as dead so they get death animations
	if animation_manager:
		# Mark leader as dead if not already
		if current_leader and is_instance_valid(current_leader):
			if not current_leader.get_meta("is_dead", false):
				current_leader.set_meta("is_dead", true)
				animation_manager.mark_unit_dead(current_leader)
		
		# Mark all remaining clones as dead
		for clone in clones:
			if is_instance_valid(clone) and not clone.get_meta("is_dead", false):
				clone.set_meta("is_dead", true)
				animation_manager.mark_unit_dead(clone)
	
	_kill_remaining_clones()
	_remove_from_groups()
	unit_died.emit(self)
	
	# Give time for death animations to start before any cleanup
	await get_tree().create_timer(0.5).timeout
	print("Squad death complete, death animations should be playing")

func _kill_remaining_clones():
	for clone in clones:
		if is_instance_valid(clone): 
			clone.set_meta("is_dead", true)
			_set_unit_visibility_and_collision(clone, false)
			clone_targets.erase(clone)
			clone_attack_timers.erase(clone.get_instance_id())

func _remove_from_groups():
	for group in ["allies", "axis"]:
		if is_in_group(group): remove_from_group(group)

# LEADERSHIP UTILITY METHODS
func get_current_leader() -> Node3D:
	return current_leader

func is_original_leader_alive() -> bool:
	return not original_leader.get_meta("is_dead", false)

func get_leadership_status() -> Dictionary:
	return {
		"current_leader": current_leader,
		"is_original_leader": leader_is_original,
		"original_leader_alive": is_original_leader_alive(),
		"succession_enabled": leadership_succession_enabled
	}

func set_leadership_succession_enabled(enabled: bool):
	leadership_succession_enabled = enabled

func _on_navigation_finished(): pass

func is_in_combat() -> bool: 
	return current_enemy != null and is_instance_valid(current_enemy)

# DEBUG AND HELPER METHODS
func force_target_validation():
	"""Public method to force target validation - useful for debugging"""
	print("Forcing target validation for squad: ", squad_id)
	_validate_current_targets()

func get_targeting_debug_info() -> Dictionary:
	"""Debug method to get targeting information"""
	var debug_info = {
		"current_enemy": current_enemy.name if current_enemy and is_instance_valid(current_enemy) else "none",
		"current_enemy_valid": _is_enemy_truly_valid(current_enemy) if current_enemy else false,
		"clone_targets": {},
		"current_leader": current_leader.name if current_leader else "none",
		"leader_is_original": leader_is_original,
		"alive_members": alive_members
	}
	
	for clone in clone_targets.keys():
		var target = clone_targets[clone]
		debug_info.clone_targets[clone.name] = {
			"target": target.name if target and is_instance_valid(target) else "none",
			"target_valid": _is_enemy_truly_valid(target) if target else false
		}
	
	return debug_info

# ANIMATION INTEGRATION METHODS
func get_animation_debug_info() -> Dictionary:
	"""Get animation debug information"""
	if animation_manager:
		return animation_manager.get_animation_debug_info()
	return {}

func force_animation_update():
	"""Force immediate animation update for all units"""
	if animation_manager:
		animation_manager.force_animation_update()

func register_new_clone_for_animation(clone: Node3D):
	"""Register a new clone with the animation manager"""
	if animation_manager:
		animation_manager.register_new_unit(clone)

func unregister_unit_from_animation(unit: Node3D):
	"""Remove a unit from animation management"""
	if animation_manager:
		animation_manager.unregister_unit(unit)

# DEBUG METHOD FOR ATTACK TIMING
func debug_attack_timing():
	"""Debug method to check attack interval values"""
	print("=== ATTACK TIMING DEBUG ===")
	print("Stats object: ", stats)
	if stats:
		print("Stats attack_interval: ", stats.attack_interval)
	print("Current attack_interval variable: ", attack_interval)
	print("Attack timer current value: ", attack_timer)
	print("Time until next attack: ", attack_interval - attack_timer)
	print("Leader can attack: ", current_enemy != null and current_leader != null)
	print("==========================")
