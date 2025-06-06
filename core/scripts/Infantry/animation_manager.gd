extends Node
class_name SquadAnimationManager

@export var squad_unit: SquadUnit

# Animation tracking per unit
var unit_animators: Dictionary = {}  # Node3D -> AnimationPlayer
var unit_states: Dictionary = {}     # Node3D -> UnitAnimationState
var last_positions: Dictionary = {}  # Node3D -> Vector3

# Combat timing
var movement_threshold: float = 0.1
var grace_period: float = 1.5
var fire_duration: float = 0.5
var cover_grace_duration: float = 0.3

class UnitAnimationState:
	var last_played_animation: String = ""
	var is_dead_and_animated: bool = false
	var unit_is_dead: bool = false
	var time_target_acquired: float = 0.0
	var has_aimed: bool = false
	var next_fire_time: float = 0.0
	var last_enemy_seen_time: float = 0.0
	var fire_start_time: float = 0.0
	var was_moving: bool = false
	var last_cover_state: bool = false
	var cover_transition_time: float = 0.0
	var is_currently_firing: bool = false  # NEW: Track if unit is currently showing fire animation
	var fire_animation_duration: float = 0.5  # NEW: How long to show fire animation

func _ready():
	if not squad_unit:
		squad_unit = find_squad_unit()
	
	if squad_unit:
		# Connect to squad signals
		squad_unit.leader_changed.connect(_on_leadership_changed)
		squad_unit.unit_died.connect(_on_unit_died)
		
		# Initialize original leader
		_register_unit(squad_unit.original_leader)
		
		# Wait a frame for clones to be created
		await get_tree().process_frame
		_register_all_clones()

func find_squad_unit() -> SquadUnit:
	var node = get_parent()
	while node:
		if node is SquadUnit:
			return node
		node = node.get_parent()
	return null

func _register_unit(unit: Node3D):
	"""Register a unit for animation management"""
	if not unit or unit_states.has(unit):
		return
	
	# Find animation player
	var anim_player = _find_animation_player(unit)
	if not anim_player:
		print("Warning: No AnimationPlayer found for unit ", unit.name)
		return
	
	# Initialize tracking
	unit_animators[unit] = anim_player
	unit_states[unit] = UnitAnimationState.new()
	last_positions[unit] = unit.global_transform.origin
	
	print("Registered unit for animation: ", unit.name)

func _find_animation_player(unit: Node3D) -> AnimationPlayer:
	"""Recursively find AnimationPlayer in unit hierarchy"""
	for child in unit.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		if child is Node3D:
			var found = _find_animation_player(child as Node3D)
			if found:
				return found
	
	return null

func _register_all_clones():
	"""Register all existing clones for animation"""
	if not squad_unit:
		return
	
	for clone in squad_unit.clones:
		if is_instance_valid(clone):
			_register_unit(clone)

func _physics_process(delta: float):
	if not squad_unit:
		return
	
	# If squad is dead, only process death animations, then stop processing
	if squad_unit.is_dead:
		_ensure_all_units_have_death_animations()
		return
	
	# Update animations for all registered units
	for unit in unit_states.keys():
		if not is_instance_valid(unit):
			continue
		
		_update_unit_animation(unit, delta)

func _ensure_all_units_have_death_animations():
	"""Make sure all units are playing death animations when squad is dead"""
	for unit in unit_states.keys():
		if not is_instance_valid(unit):
			continue
			
		var state = unit_states[unit]
		var animator = unit_animators.get(unit)
		
		if not animator or not state:
			continue
		
		# If unit should be dead but hasn't played death animation yet
		if not state.is_dead_and_animated:
			print("Force-triggering death animation for: ", unit.name)
			_play_death_animation(unit, animator, state)
			state.is_dead_and_animated = true
			state.unit_is_dead = true

func _update_unit_animation(unit: Node3D, delta: float):
	"""Update animation for a specific unit"""
	var state = unit_states[unit]
	var animator = unit_animators.get(unit)
	
	if not animator or not state:
		return
	
	# Check if unit is dead
	var should_play_death = _is_unit_dead(unit)
	
	if should_play_death and not state.is_dead_and_animated:
		_play_death_animation(unit, animator, state)
		state.is_dead_and_animated = true
		state.unit_is_dead = true
		return
	
	# If unit is dead and already animated, don't update further
	# This preserves the death animation
	if should_play_death or state.unit_is_dead:
		# Only return if NOT playing a death animation
		# If death animation finished, let it stay in final pose
		return
	
	# Update combat timing and determine animation for living units
	_update_unit_combat_timing(unit, state)
	var new_animation = _determine_unit_animation(unit, state)
	
	if new_animation != state.last_played_animation:
		_play_unit_animation(unit, animator, new_animation, state)
		state.last_played_animation = new_animation

func _is_unit_dead(unit: Node3D) -> bool:
	"""Check if a specific unit is dead"""
	if not unit or not is_instance_valid(unit):
		return true
	
	var state = unit_states.get(unit)
	if state and state.unit_is_dead:
		return true
	
	# Check if this is the original leader
	if unit == squad_unit.original_leader:
		return squad_unit.is_dead or squad_unit.original_leader.get_meta("is_dead", false)
	else:
		# For clones
		return unit.get_meta("is_dead", false)

# NEW: Method called by SquadUnit when a unit actually fires
func trigger_unit_fire_animation(unit: Node3D):
	"""Called by SquadUnit when a unit actually fires - uses configurable duration"""
	var state = unit_states.get(unit)
	if not state or state.unit_is_dead:
		return
	
	var animator = unit_animators.get(unit)
	if not animator:
		return
	
	# Get fire animation duration from CombatUnitData
	var fire_duration = squad_unit.stats.fire_animation_duration if squad_unit.stats else 0.5
	state.fire_animation_duration = fire_duration
	
	# Mark this unit as currently firing
	state.is_currently_firing = true
	state.fire_start_time = Time.get_ticks_msec() / 1000.0
	
	# Force immediate animation update to show fire animation
	var in_heavy_cover = unit.get_meta("in_heavy_cover", false)
	var fire_anim = "Crouch_Fire" if in_heavy_cover else "Fire"
	_play_unit_animation(unit, animator, fire_anim, state)
	state.last_played_animation = fire_anim
	
	print("Animation: Triggered fire animation for ", unit.name, " - ", fire_anim, " (duration: ", fire_duration, "s)")

func _update_unit_combat_timing(unit: Node3D, state: UnitAnimationState):
	"""Combat timing that uses configurable aim time from CombatUnitData"""
	var now = Time.get_ticks_msec() / 1000.0
	var enemy = _get_unit_target(unit)
	
	# Get aim time from CombatUnitData
	var aim_time = squad_unit.stats.aim_time_before_fire if squad_unit.stats else 1.2
	
	if enemy != null and is_instance_valid(enemy):
		state.last_enemy_seen_time = now
		if state.time_target_acquired == 0.0:
			state.time_target_acquired = now
			state.has_aimed = false
		elif not state.has_aimed and now - state.time_target_acquired >= aim_time:
			state.has_aimed = true
	elif now - state.last_enemy_seen_time > grace_period:
		_reset_unit_combat_timing(state)
	
	# Handle fire animation duration (now configurable)
	if state.is_currently_firing:
		if now - state.fire_start_time >= state.fire_animation_duration:
			state.is_currently_firing = false
			state.fire_start_time = 0.0

func get_animation_timing_debug() -> Dictionary:
	"""Get debug info about animation timing settings"""
	if not squad_unit or not squad_unit.stats:
		return {
			"fire_animation_duration": 0.5,
			"aim_time_before_fire": 1.2,
			"source": "defaults"
		}
	
	return {
		"fire_animation_duration": squad_unit.stats.fire_animation_duration,
		"aim_time_before_fire": squad_unit.stats.aim_time_before_fire,
		"source": "CombatUnitData"
	}

func _get_unit_target(unit: Node3D) -> Node:
	"""Get the target for a specific unit"""
	if unit == squad_unit.current_leader:
		return squad_unit.current_enemy
	else:
		return squad_unit.clone_targets.get(unit, null)

func _determine_unit_animation(unit: Node3D, state: UnitAnimationState) -> String:
	"""Determine what animation a unit should play"""
	if state.unit_is_dead or _is_unit_dead(unit):
		var animator = unit_animators.get(unit)
		return "Death_1" if animator and animator.has_animation("Death_1") else "Idle_1"
	
	var is_moving = _is_unit_moving(unit, state)
	var enemy_target = _get_unit_target(unit)
	var is_attacking = enemy_target != null and is_instance_valid(enemy_target)
	var current_cover_state = unit.get_meta("in_heavy_cover", false)
	var now = Time.get_ticks_msec() / 1000.0
	var in_heavy_cover = _get_effective_cover_state(unit, current_cover_state, now, state)
	
	# Reset combat timing when movement state changes
	if is_moving and not state.was_moving:
		_reset_unit_combat_timing(state)
	elif state.was_moving and not is_moving:
		_reset_unit_combat_timing(state)
	
	state.was_moving = is_moving
	
	# If unit is currently firing (triggered by SquadUnit), show fire animation
	if state.is_currently_firing:
		return "Crouch_Fire" if in_heavy_cover else "Fire"
	
	if is_attacking:
		if is_moving:
			return "Crouch_Move" if in_heavy_cover else "Move"
		elif not state.has_aimed:
			return "Crouch" if in_heavy_cover else "Aim"
		else:
			# Has aimed and has target, but not currently firing
			return "Crouch" if in_heavy_cover else "Aim"
	
	if is_moving:
		return "Crouch_Move" if in_heavy_cover else "Move"
	else:
		return "Crouch" if in_heavy_cover else "Idle_1"

func _is_unit_moving(unit: Node3D, state: UnitAnimationState) -> bool:
	"""Check if a specific unit is moving"""
	if not unit or state.unit_is_dead:
		return false
	
	var in_heavy_cover = unit.get_meta("in_heavy_cover", false)
	var current_position = unit.global_transform.origin
	var last_pos = last_positions.get(unit, current_position)
	var distance_moved = current_position.distance_to(last_pos)
	last_positions[unit] = current_position
	
	if in_heavy_cover and distance_moved > 0.05:
		return true
	
	if distance_moved > movement_threshold:
		return true
	
	# Check navigation agent
	if unit == squad_unit.original_leader:
		if squad_unit.nav_agent and not squad_unit.nav_agent.is_navigation_finished():
			return true
	else:
		var clone_nav = unit.get_node_or_null("NavigationAgent3D")
		if clone_nav and not clone_nav.is_navigation_finished():
			return true
	
	return false

func _play_unit_animation(unit: Node3D, animator: AnimationPlayer, anim_name: String, state: UnitAnimationState):
	"""Play animation for a specific unit"""
	if state.unit_is_dead or _is_unit_dead(unit):
		return
	
	var in_heavy_cover = unit.get_meta("in_heavy_cover", false)
	
	if animator.has_animation(anim_name):
		animator.play(anim_name)
	else:
		# Try fallback animations
		if in_heavy_cover:
			var fallback = ""
			if anim_name == "Crouch":
				fallback = "Aim"
			elif anim_name == "Crouch_Fire":
				fallback = "Fire"
			elif anim_name == "Crouch_Move":
				fallback = "Move"
			
			if fallback != "" and animator.has_animation(fallback):
				animator.play(fallback)

func _play_death_animation(unit: Node3D, animator: AnimationPlayer, state: UnitAnimationState):
	"""Play death animation for a unit"""
	var death_animations = ["Death_1", "Death_2", "Death_3"]
	var available_death_anims: Array[String] = []
	
	for anim in death_animations:
		if animator.has_animation(anim):
			available_death_anims.append(anim)
	
	if available_death_anims.size() > 0:
		var random_death = available_death_anims[randi() % available_death_anims.size()]
		animator.stop()
		animator.play(random_death)
		
		print("Playing death animation: ", random_death, " for unit: ", unit.name)
		
		# Set animation to non-looping and ensure it stays in final pose
		await get_tree().process_frame
		var animation_resource = animator.get_animation(random_death)
		if animation_resource:
			animation_resource.loop_mode = Animation.LOOP_NONE
			
		# Wait for animation to finish, then lock it in final pose
		if animation_resource:
			var anim_length = animation_resource.length
			await get_tree().create_timer(anim_length).timeout
			
			# Lock the animation at the final frame
			animator.seek(anim_length, true)
			animator.pause()
			print("Locked death animation in final pose for: ", unit.name)

func _reset_unit_combat_timing(state: UnitAnimationState):
	"""Reset combat timing for a unit"""
	state.time_target_acquired = 0.0
	state.has_aimed = false
	state.next_fire_time = 0.0
	state.fire_start_time = 0.0
	state.is_currently_firing = false  # NEW: Reset firing state

func _get_effective_cover_state(unit: Node3D, current_state: bool, current_time: float, state: UnitAnimationState) -> bool:
	"""Get effective cover state with grace period"""
	if current_state != state.last_cover_state:
		state.last_cover_state = current_state
		state.cover_transition_time = current_time
		if current_state:
			return true
	
	if current_time - state.cover_transition_time < cover_grace_duration:
		if not current_state and state.last_cover_state:
			return true
		elif current_state:
			return true
	
	return current_state

# Signal handlers
func _on_leadership_changed(new_leader: Node3D):
	"""Handle leadership changes"""
	print("Squad animation manager: Leadership changed to ", new_leader.name if new_leader else "None")
	
	# Reset combat timing for all units to prevent stuck animations
	for unit in unit_states.keys():
		var state = unit_states[unit]
		_reset_unit_combat_timing(state)
		state.last_played_animation = ""

func _on_unit_died(dead_unit: SquadUnit):
	"""Handle unit death - this is for the squad itself dying"""
	print("Squad animation manager: Squad died, leaving death animations intact")
	# Don't clean up anything - let death animations stay as they are

# Public methods
func register_new_unit(unit: Node3D):
	"""Public method to register a new unit (e.g., newly spawned clone)"""
	_register_unit(unit)

func unregister_unit(unit: Node3D):
	"""Remove a unit from animation management"""
	if unit_states.has(unit):
		unit_states.erase(unit)
	if unit_animators.has(unit):
		unit_animators.erase(unit)
	if last_positions.has(unit):
		last_positions.erase(unit)
	
	print("Unregistered unit from animation: ", unit.name if unit else "Unknown")

func mark_unit_dead(unit: Node3D):
	"""Mark a specific unit as dead"""
	var state = unit_states.get(unit)
	if state:
		state.unit_is_dead = true
		_reset_unit_combat_timing(state)
		print("Marked unit as dead for animation: ", unit.name)

func _cleanup_all_animations():
	"""Clean up all animation tracking - but leave animations playing"""
	# Just clear the tracking data, don't stop any animations
	unit_states.clear()
	unit_animators.clear()
	last_positions.clear()
	print("Animation manager: Cleared tracking data but left animations intact")

# Debug methods
func get_animation_debug_info() -> Dictionary:
	"""Get debug information about current animation states"""
	var debug_info = {}
	
	for unit in unit_states.keys():
		if not is_instance_valid(unit):
			continue
		
		var state = unit_states[unit]
		var animator = unit_animators.get(unit)
		
		debug_info[unit.name] = {
			"current_animation": animator.current_animation if animator else "None",
			"is_dead": state.unit_is_dead,
			"has_aimed": state.has_aimed,
			"is_attacking": _get_unit_target(unit) != null,
			"last_played": state.last_played_animation,
			"is_currently_firing": state.is_currently_firing,
			"fire_start_time": state.fire_start_time
		}
	
	return debug_info

func force_animation_update():
	"""Force immediate animation update for all units"""
	for unit in unit_states.keys():
		if is_instance_valid(unit):
			var state = unit_states[unit]
			state.last_played_animation = ""  # Force refresh
			
