extends Node3D
@export var move_marker_scene: PackedScene  # Assign in Inspector
var selected_unit: Node = null
var camera: Camera3D = null
var move_marker: Node3D = null  # Reference to spawned marker

func _ready():
	var rig: Node = get_tree().get_current_scene().get_node_or_null("CameraRig")
	if rig:
		camera = rig.get_node_or_null("Camera3D")
	if camera == null:
		push_error("SelectionManager: Could not find CameraRig/Camera3D.")

func _unhandled_input(event):
	if camera == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_unit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and selected_unit:
			command_unit_move()

func select_unit():
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		print("Nothing hit.")
		deselect_unit()
		hide_move_marker()
		return
	
	var hit: Node = result.get("collider", null)
	print("Raycast hit:", hit.name)
	print("Hit node type:", hit.get_class())
	print("Hit node groups:", hit.get_groups())
	
	var target_unit: Node = null
	var current: Node = hit
	
	# First, check if we hit a squad leader directly
	while current != null:
		if current.get_script() != null and current.get_script().get_global_name() == "SquadUnit":
			# This is a squad leader
			target_unit = current
			print("Found squad leader directly:", current.name)
			break
		elif current.is_in_group("infantry"):
			# If we hit a clone or infantry unit, find its squad leader
			if current.has_meta("squad_id"):
				var squad_id = current.get_meta("squad_id")
				print("Hit clone with squad_id:", squad_id)
				target_unit = _find_squad_by_id(squad_id)
				if target_unit:
					print("Found squad leader via squad_id:", target_unit.name)
				break
			else:
				# This might be a squad leader without squad_id meta
				# Check if it has SquadUnit methods
				if current.has_method("move_to_position") and current.has_method("take_damage"):
					target_unit = current
					print("Found squad leader by methods:", current.name)
					break
		current = current.get_parent()
	
	if target_unit == null:
		print("No selectable unit found.")
		deselect_unit()
		hide_move_marker()
		return
	
	# Deselect previous unit if different
	if selected_unit and selected_unit != target_unit:
		selected_unit.is_selected = false
	
	selected_unit = target_unit
	selected_unit.is_selected = true
	print("Selected:", target_unit.name)

func _find_squad_by_id(squad_id: String) -> Node:
	# Search in both allied and axis groups
	var all_squads = get_tree().get_nodes_in_group("allies") + get_tree().get_nodes_in_group("axis")
	for squad in all_squads:
		# Check if this squad has the matching squad_id
		if squad.has_method("get") and squad.get("squad_id") == squad_id:
			return squad
		# Alternative check using property access
		elif "squad_id" in squad and squad.squad_id == squad_id:
			return squad
	
	print("Could not find squad with ID:", squad_id)
	return null

func deselect_unit():
	if selected_unit:
		selected_unit.is_selected = false
		selected_unit = null

func hide_move_marker():
	if move_marker and is_instance_valid(move_marker):
		move_marker.visible = false

func command_unit_move():
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1
	
	var result: Dictionary = space_state.intersect_ray(query)
	print("Right-click raycast result:", result)
	
	if result.is_empty() or not result.has("position"):
		print("No ground hit for movement.")
		return
	
	var position: Vector3 = result["position"]
	if position == Vector3.ZERO:
		print("Aborting move — invalid target position.")
		return
	
	print("Commanded move to:", position)
	selected_unit.move_to_position(position)
	
	if move_marker_scene:
		if move_marker == null or not is_instance_valid(move_marker):
			move_marker = move_marker_scene.instantiate()
			get_tree().get_current_scene().add_child(move_marker)
		move_marker.global_transform.origin = position
		move_marker.visible = true
