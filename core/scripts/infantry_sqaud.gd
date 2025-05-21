extends CharacterBody3D

@export var stats: CombatUnitData

@onready var infantry_template: Node3D = $Infantry
@onready var nav_agent: NavigationAgent3D = $Infantry/NavigationAgent3D
@onready var anim_player: AnimationPlayer = $Infantry/AnimationPlayer
@onready var selection_ring: Node3D = $Infantry/SelectionRing

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

func _ready():
	if anim_player:
		anim_player.play("Idle_1")
	if selection_ring:
		selection_ring.visible = false

	if stats:
		_spawn_infantry_clones(stats.squad_size)
	else:
		push_warning("CombatUnitData 'stats' not assigned!")

func _spawn_infantry_clones(count: int):
	var num_clones = count - 1
	var spacing = 3.5

	var container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if container == null:
		push_error("Missing 'CloneContainer' node in scene.")
		return

	for i in num_clones:
		var clone = infantry_template.duplicate()
		clone.name = "InfantryClone_%d" % i

		var row = i / 3
		var col = i % 3
		var offset = Vector3(
			(col - 1) * spacing + randf_range(-0.5, 0.5),
			0,
			-(row + 1) * spacing + randf_range(-0.5, 0.5)
		)

		clone.set_meta("formation_offset", offset)

		var clone_anim = clone.get_node_or_null("AnimationPlayer")
		if clone_anim:
			clone_anim.play("Idle_1")

		container.add_child(clone)
		infantry_clones.append(clone)

func _physics_process(delta):
	if nav_agent == null:
		return

	var is_moving = not nav_agent.is_navigation_finished()

	if is_moving:
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
		if anim_player.current_animation != "Idle_1":
			anim_player.play("Idle_1")

	_process_clone_movement(delta)

func _process_clone_movement(delta):
	for clone in infantry_clones:
		if not is_instance_valid(clone):
			continue

		var offset: Vector3 = clone.get_meta("formation_offset")

		var forward = -global_transform.basis.z.normalized()
		var right = global_transform.basis.x.normalized()

		var target_pos = global_transform.origin + right * offset.x + forward * offset.z

		# Calculate flat movement vector
		var move_vec = target_pos - clone.global_transform.origin
		move_vec.y = 0

		var distance = move_vec.length()

		# Dead zone to stop jitter
		if distance < 0.05:
			var pos = clone.global_transform.origin
			pos.y = global_transform.origin.y + 0.01
			clone.global_transform.origin = pos

			var clone_anim = clone.get_node_or_null("AnimationPlayer")
			if clone_anim and clone_anim.current_animation != "Idle_1":
				clone_anim.play("Idle_1")
			continue

		var direction = move_vec.normalized()
		var speed = stats.move_speed * 0.9

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

		# ✅ Move toward formation target
		clone.global_translate(direction * speed * delta)

		# Set correct height
		var new_pos = clone.global_transform.origin
		new_pos.y = global_transform.origin.y + 0.5
		clone.global_transform.origin = new_pos

		# ✅ Rotate
		if direction.length() > 0.1:
			var target_rot = atan2(direction.x, direction.z)
			var current_rot = clone.rotation.y
			clone.rotation.y = lerp_angle(current_rot, target_rot, delta * 5.0)

		# ✅ Animate
		var clone_anim = clone.get_node_or_null("AnimationPlayer")
		if clone_anim and clone_anim.current_animation != "Move":
			clone_anim.play("Move")

func move_to_position(pos: Vector3):
	if nav_agent:
		nav_agent.set_target_position(pos)
