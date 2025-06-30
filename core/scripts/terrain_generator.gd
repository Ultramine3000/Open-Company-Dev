extends MeshInstance3D

@export var terrain_size: float = 50.0  # Total size in world units
@export var terrain_resolution: int = 50  # Number of subdivisions
@export var max_height: float = 2.0
@export var regenerate: bool = false : set = _regenerate
@export var create_material: bool = true

# Material options
@export_group("Material Settings")
@export var use_custom_material: bool = false
@export var custom_material: Material
@export var fallback_color: Color = Color.GREEN
@export var metallic: float = 0.0
@export var roughness: float = 0.8

# Enhanced scatter system with per-element probabilities
@export_group("Surface Scattering")
@export var scatter_scenes: Array[PackedScene] = []
@export var scatter_probabilities: Array[float] = []  # Probability for each scene (0.0 to 1.0)
@export var scatter_count: int = 100
@export var scatter_scale_min: float = 0.5
@export var scatter_scale_max: float = 1.5
@export var scatter_rotation_random: bool = true
@export var clear_scattered: bool = false : set = _clear_scattered
@export var normalize_probabilities: bool = true  # Auto-normalize probabilities to sum to 1.0
@export var show_scatter_stats: bool = false  # Show statistics after scattering

# Navigation mesh generation
@export_group("Navigation")
@export var create_navigation_mesh: bool = true
@export var nav_mesh_name: String = "TerrainNavigation"
@export var nav_mesh_resolution: int = 16  # Higher resolution for smaller cells
@export var show_debug_navigation: bool = false : set = _set_debug_navigation

func _ready():
	create_landscape_mesh()
	if create_material:
		setup_material()
	if create_navigation_mesh:
		create_navigation_region.call_deferred()
	if scatter_scenes.size() > 0:
		validate_scatter_probabilities()
		# Defer scattering until after the scene tree is ready
		scatter_objects_on_surface.call_deferred()

func _regenerate(value):
	if value and is_inside_tree():
		create_landscape_mesh()
		if create_navigation_mesh:
			remove_existing_navigation()
			create_navigation_region.call_deferred()
		if scatter_scenes.size() > 0:
			validate_scatter_probabilities()
			clear_all_scattered()
			scatter_objects_on_surface.call_deferred()

func _clear_scattered(value):
	if value and is_inside_tree():
		clear_all_scattered()

func validate_scatter_probabilities():
	# Ensure probabilities array matches scenes array
	if scatter_probabilities.size() != scatter_scenes.size():
		print("Adjusting probabilities array to match scenes array size")
		scatter_probabilities.resize(scatter_scenes.size())
		
		# Fill missing probabilities with equal weight
		var default_prob = 1.0 / max(1, scatter_scenes.size())
		for i in range(scatter_probabilities.size()):
			if scatter_probabilities[i] == 0.0:
				scatter_probabilities[i] = default_prob
	
	# Normalize probabilities if requested
	if normalize_probabilities:
		normalize_probability_array()
	
	# Clamp all probabilities to valid range
	for i in range(scatter_probabilities.size()):
		scatter_probabilities[i] = clamp(scatter_probabilities[i], 0.0, 1.0)

func normalize_probability_array():
	if scatter_probabilities.is_empty():
		return
	
	var total = 0.0
	for prob in scatter_probabilities:
		total += prob
	
	if total > 0.0:
		for i in range(scatter_probabilities.size()):
			scatter_probabilities[i] /= total
		print("Normalized scatter probabilities - total sum: ", total)

func create_landscape_mesh():
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	# Create vertices
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			# Convert grid position to world position
			var world_x = (float(x) / float(terrain_resolution)) * terrain_size - terrain_size * 0.5
			var world_z = (float(z) / float(terrain_resolution)) * terrain_size - terrain_size * 0.5
			
			# Create gentle, relatively level terrain with minimal height variation
			var height = (sin(world_x * 0.1) + cos(world_z * 0.1)) * max_height * 0.1
			
			var vertex = Vector3(world_x, height, world_z)
			vertices.append(vertex)
			
			# Calculate UV coordinates
			var uv = Vector2(
				float(x) / float(terrain_resolution),
				float(z) / float(terrain_resolution)
			)
			uvs.append(uv)
			
			# Simple upward normal (we'll calculate proper ones later)
			normals.append(Vector3.UP)
	
	# Create triangles
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var i = z * (terrain_resolution + 1) + x
			
			# First triangle
			indices.append(i)
			indices.append(i + terrain_resolution + 1)
			indices.append(i + 1)
			
			# Second triangle  
			indices.append(i + 1)
			indices.append(i + terrain_resolution + 1)
			indices.append(i + terrain_resolution + 2)
	
	# Calculate proper normals
	normals = calculate_normals(vertices, indices)
	
	# Assign arrays to surface
	surface_array[Mesh.ARRAY_VERTEX] = vertices
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_INDEX] = indices
	
	# Create the mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	# Assign to this MeshInstance3D
	mesh = array_mesh
	
	print("Landscape mesh created with ", vertices.size(), " vertices")
	print("Mesh bounds: ", array_mesh.get_aabb())

func setup_material():
	var material: Material
	
	if use_custom_material and custom_material:
		# Use the custom material (could be shader material)
		material = custom_material
		print("Using custom material: ", custom_material.get_class())
	else:
		# Create default StandardMaterial3D
		var standard_material = StandardMaterial3D.new()
		standard_material.albedo_color = fallback_color
		standard_material.metallic = metallic
		standard_material.roughness = roughness
		standard_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
		standard_material.flags_unshaded = false
		standard_material.flags_use_point_size = false
		material = standard_material
		print("Using default StandardMaterial3D")
	
	set_surface_override_material(0, material)

func calculate_normals(verts: PackedVector3Array, inds: PackedInt32Array) -> PackedVector3Array:
	var normals = PackedVector3Array()
	normals.resize(verts.size())
	
	# Initialize all normals to zero
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO
	
	# Calculate face normals and add to vertex normals
	for i in range(0, inds.size(), 3):
		var i0 = inds[i]
		var i1 = inds[i + 1] 
		var i2 = inds[i + 2]
		
		var v0 = verts[i0]
		var v1 = verts[i1]
		var v2 = verts[i2]
		
		var face_normal = (v1 - v0).cross(v2 - v0).normalized()
		
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal
	
	# Normalize all vertex normals
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	
	return normals

func scatter_objects_on_surface():
	if scatter_scenes.is_empty():
		print("No scatter scenes assigned!")
		return
	
	if not mesh:
		print("No mesh found! Generate terrain first.")
		return
	
	clear_all_scattered()
	validate_scatter_probabilities()
	
	# Get all the vertices from the mesh to place objects on actual mesh points
	var mesh_vertices = get_mesh_vertices()
	if mesh_vertices.is_empty():
		print("Could not get mesh vertices!")
		return
	
	# Track statistics
	var spawn_counts = {}
	for i in range(scatter_scenes.size()):
		spawn_counts[i] = 0
	
	# Create cumulative probability distribution for weighted selection
	var cumulative_probs = []
	var running_total = 0.0
	for prob in scatter_probabilities:
		running_total += prob
		cumulative_probs.append(running_total)
	
	# Normalize cumulative probabilities to ensure they sum to 1.0
	if running_total > 0.0:
		for i in range(cumulative_probs.size()):
			cumulative_probs[i] /= running_total
	
	print("Scatter probabilities: ", scatter_probabilities)
	print("Cumulative probabilities: ", cumulative_probs)
	
	for i in range(scatter_count):
		# Select scene based on probability weights
		var scene_index = select_scene_by_probability(cumulative_probs)
		var scene_to_spawn = scatter_scenes[scene_index]
		
		if not scene_to_spawn:
			continue
		
		# Track what we spawned
		spawn_counts[scene_index] += 1
		
		# Pick a random vertex from the mesh
		var vertex_pos = mesh_vertices[randi() % mesh_vertices.size()]
		
		# Convert to world position
		var world_pos = to_global(vertex_pos)
		
		# Random scale
		var scale = randf_range(scatter_scale_min, scatter_scale_max)
		
		# Instance the scene
		var instance = scene_to_spawn.instantiate()
		get_parent().add_child.call_deferred(instance)
		
		# Position it (defer this too to ensure the instance is added first)
		_setup_scattered_object.call_deferred(instance, world_pos, scale)
	
	# Show statistics if requested
	if show_scatter_stats:
		print_scatter_statistics(spawn_counts)
	
	print("Scattered ", scatter_count, " objects on mesh surface using probability weights")

func select_scene_by_probability(cumulative_probs: Array) -> int:
	if cumulative_probs.is_empty():
		return 0
	
	var random_value = randf()
	
	for i in range(cumulative_probs.size()):
		if random_value <= cumulative_probs[i]:
			return i
	
	# Fallback to last scene (should rarely happen)
	return cumulative_probs.size() - 1

func print_scatter_statistics(spawn_counts: Dictionary):
	print("\n=== Scatter Statistics ===")
	var total_spawned = 0
	
	for scene_index in spawn_counts.keys():
		var count = spawn_counts[scene_index]
		total_spawned += count
		var expected_prob = scatter_probabilities[scene_index] if scene_index < scatter_probabilities.size() else 0.0
		var actual_prob = float(count) / float(scatter_count) if scatter_count > 0 else 0.0
		var scene_name = scatter_scenes[scene_index].resource_path.get_file() if scene_index < scatter_scenes.size() else "Unknown"
		
		print("Scene %d (%s): %d spawned (%.1f%%) - Expected: %.1f%%" % [
			scene_index, 
			scene_name,
			count, 
			actual_prob * 100.0, 
			expected_prob * 100.0
		])
	
	print("Total spawned: %d / %d" % [total_spawned, scatter_count])
	print("========================\n")

func get_mesh_vertices() -> PackedVector3Array:
	if not mesh or not mesh is ArrayMesh:
		return PackedVector3Array()
	
	var array_mesh = mesh as ArrayMesh
	if array_mesh.get_surface_count() == 0:
		return PackedVector3Array()
	
	var surface_arrays = array_mesh.surface_get_arrays(0)
	if surface_arrays.size() <= Mesh.ARRAY_VERTEX:
		return PackedVector3Array()
	
	return surface_arrays[Mesh.ARRAY_VERTEX]

func _setup_scattered_object(instance: Node3D, pos: Vector3, scale_value: float):
	# This runs after the instance is properly added to the tree
	instance.global_position = pos
	instance.scale = Vector3(scale_value, scale_value, scale_value)
	
	# Random rotation if enabled
	if scatter_rotation_random:
		instance.rotation.y = randf() * TAU
	
	# Tag it for cleanup
	instance.set_meta("scattered_object", true)

func get_height_at_position(x: float, z: float) -> float:
	# Same height calculation as used in mesh generation - keep it level
	return (sin(x * 0.1) + cos(z * 0.1)) * max_height * 0.1

func clear_all_scattered():
	# Find and remove all scattered objects
	var parent = get_parent()
	var children_to_remove = []
	
	for child in parent.get_children():
		if child.has_meta("scattered_object"):
			children_to_remove.append(child)
	
	for child in children_to_remove:
		child.queue_free()
	
	print("Cleared scattered objects")

# Helper function to set equal probabilities for all scenes
func set_equal_probabilities():
	if scatter_scenes.is_empty():
		return
	
	var equal_prob = 1.0 / scatter_scenes.size()
	scatter_probabilities.clear()
	for i in range(scatter_scenes.size()):
		scatter_probabilities.append(equal_prob)
	
	print("Set equal probabilities (%.3f) for all %d scenes" % [equal_prob, scatter_scenes.size()])

# Helper function to set specific probability for a scene
func set_scene_probability(scene_index: int, probability: float):
	if scene_index < 0 or scene_index >= scatter_scenes.size():
		print("Invalid scene index: ", scene_index)
		return
	
	if scatter_probabilities.size() != scatter_scenes.size():
		scatter_probabilities.resize(scatter_scenes.size())
	
	scatter_probabilities[scene_index] = clamp(probability, 0.0, 1.0)
	
	if normalize_probabilities:
		normalize_probability_array()

func create_navigation_region():
	if not mesh:
		print("No mesh found for navigation generation!")
		return
	
	# Remove any existing navigation region
	remove_existing_navigation()
	
	# Create NavigationRegion3D as sibling
	var nav_region = NavigationRegion3D.new()
	nav_region.name = nav_mesh_name
	get_parent().add_child(nav_region)
	
	# Create NavigationMesh resource
	var nav_mesh = NavigationMesh.new()
	
	# Configure navigation mesh settings to match default map settings
	nav_mesh.cell_size = 0.25  # Match the navigation map's cell size
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0
	
	# Assign the navigation mesh to the region
	nav_region.navigation_mesh = nav_mesh
	
	# Create navigation mesh procedurally from our terrain data (more efficient)
	create_navigation_mesh_procedurally(nav_mesh)
	
	# Enable debug visualization if requested
	if show_debug_navigation:
		enable_navigation_debug(nav_region)
	
	print("Navigation mesh created: ", nav_mesh_name)

func create_navigation_mesh_procedurally(nav_mesh: NavigationMesh):
	# Create vertices and indices arrays for the navigation mesh
	var nav_vertices = PackedVector3Array()
	
	# Use even lower resolution for navigation mesh (smoother pathfinding)
	var nav_res = nav_mesh_resolution
	
	# Calculate navigation mesh size (smaller than terrain)
	# If terrain is 1.5x bigger, then nav mesh should be terrain_size / 1.5
	var nav_mesh_size = terrain_size / 1.5
	
	# Generate vertices with simplified grid using smaller nav mesh size
	for z in range(nav_res + 1):
		for x in range(nav_res + 1):
			var world_x = (float(x) / float(nav_res)) * nav_mesh_size - nav_mesh_size * 0.5
			var world_z = (float(z) / float(nav_res)) * nav_mesh_size - nav_mesh_size * 0.5
			var height = (sin(world_x * 0.1) + cos(world_z * 0.1)) * max_height * 0.1
			
			nav_vertices.append(Vector3(world_x, height, world_z))
	
	# Set the navigation mesh geometry directly
	nav_mesh.vertices = nav_vertices
	
	# Clear any existing polygons and add new ones
	nav_mesh.clear_polygons()
	
	# Create larger polygons by combining multiple quads
	var step = 1  # Use individual quads for smaller cells
	for z in range(0, nav_res - step + 1, step):
		for x in range(0, nav_res - step + 1, step):
			# Create a single quad polygon
			var polygon = PackedInt32Array()
			var i = z * (nav_res + 1) + x
			
			# Simple quad (4 vertices)
			polygon.append(i)
			polygon.append(i + 1)
			polygon.append(i + nav_res + 2)
			polygon.append(i + nav_res + 1)
			
			nav_mesh.add_polygon(polygon)

func enable_navigation_debug(nav_region: NavigationRegion3D):
	# Enable debug drawing for the navigation region
	nav_region.enabled = true
	
	# Enable global navigation debug visualization
	var debug_settings = NavigationServer3D.get_debug_enabled()
	if not debug_settings:
		NavigationServer3D.set_debug_enabled(true)
	
	# Optional: Create a visual debug mesh overlay
	create_debug_mesh_overlay(nav_region)

func create_debug_mesh_overlay(nav_region: NavigationRegion3D):
	# Create a wireframe overlay to visualize navigation polygons
	var debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "NavDebugMesh"
	nav_region.add_child(debug_mesh_instance)
	
	var nav_mesh = nav_region.navigation_mesh
	if not nav_mesh:
		return
	
	var vertices = nav_mesh.vertices
	var debug_vertices = PackedVector3Array()
	var debug_indices = PackedInt32Array()
	
	# Create wireframe lines for each polygon
	for i in range(nav_mesh.get_polygon_count()):
		var polygon = nav_mesh.get_polygon(i)
		
		# Create lines around the polygon perimeter
		for j in range(polygon.size()):
			var current_vertex = vertices[polygon[j]]
			var next_vertex = vertices[polygon[(j + 1) % polygon.size()]]
			
			debug_vertices.append(current_vertex + Vector3(0, 0.1, 0))  # Slightly above terrain
			debug_vertices.append(next_vertex + Vector3(0, 0.1, 0))
	
	# Create indices for lines
	for i in range(0, debug_vertices.size(), 2):
		debug_indices.append(i)
		debug_indices.append(i + 1)
	
	# Create the debug mesh
	var debug_arrays = []
	debug_arrays.resize(Mesh.ARRAY_MAX)
	debug_arrays[Mesh.ARRAY_VERTEX] = debug_vertices
	debug_arrays[Mesh.ARRAY_INDEX] = debug_indices
	
	var debug_array_mesh = ArrayMesh.new()
	debug_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, debug_arrays)
	debug_mesh_instance.mesh = debug_array_mesh
	
	# Create a bright material for visibility
	var debug_material = StandardMaterial3D.new()
	debug_material.albedo_color = Color.CYAN
	debug_material.flags_unshaded = true
	debug_material.flags_use_point_size = false
	debug_material.flags_transparent = true
	debug_material.no_depth_test = true
	debug_mesh_instance.set_surface_override_material(0, debug_material)

func _set_debug_navigation(value):
	show_debug_navigation = value
	if is_inside_tree():
		_update_debug_visualization()

func _update_debug_visualization():
	var parent = get_parent()
	var nav_region = parent.get_node_or_null(nav_mesh_name)
	if not nav_region:
		return
	
	# Find and remove existing debug mesh
	var debug_mesh = nav_region.get_node_or_null("NavDebugMesh")
	if debug_mesh:
		debug_mesh.queue_free()
	
	# Enable/disable global debug and create new debug mesh if needed
	NavigationServer3D.set_debug_enabled(show_debug_navigation)
	
	if show_debug_navigation:
		enable_navigation_debug(nav_region)

func remove_existing_navigation():
	var parent = get_parent()
	var existing_nav = parent.get_node_or_null(nav_mesh_name)
	if existing_nav:
		existing_nav.queue_free()
