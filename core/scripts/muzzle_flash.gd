extends Node

# References to the sibling AnimationPlayer and child emitter
@onready var animation_player: AnimationPlayer
@onready var emitter: GPUParticles3D  # Change to GPUParticles3D or CPUParticles2D/3D as needed

# Tracer settings
var tracer_scene: PackedScene  # Assign your tracer scene in the inspector
var tracer_speed: float = 200.0  # Speed of tracer movement
var tracer_max_distance: float = 100.0  # Maximum distance tracer travels
var muzzle_offset: Vector3 = Vector3.ZERO  # Offset from model origin for muzzle position

func _ready():
	# Get the sibling AnimationPlayer
	animation_player = get_parent().get_node("AnimationPlayer")  # Adjust path if needed
	tracer_scene = preload("res://scenes/tracer.tscn")
	
	# Get the child emitter
	emitter = get_child(0)  # Assumes emitter is first child, or use get_node("EmitterName")
	
	# Connect to the animation_started signal if it exists, otherwise use animation_changed
	if animation_player.has_signal("animation_started"):
		animation_player.animation_started.connect(_on_animation_started)
	else:
		# Fallback: monitor current animation changes
		animation_player.animation_changed.connect(_on_animation_changed)
	
	# Make sure emitter starts disabled
	if emitter:
		emitter.emitting = false

func _on_animation_started(animation_name: String):
	if animation_name == "Fire":
		activate_muzzle_flash()
		spawn_tracer_with_collision()

func _on_animation_changed():
	# Check if the current animation is "Fire" and it's playing
	if animation_player.current_animation == "Fire" and animation_player.is_playing():
		activate_muzzle_flash()
		spawn_tracer_with_collision()

func activate_muzzle_flash():
	if emitter:
		emitter.emitting = true
		# Optional: Auto-disable after a short duration
		create_tween().tween_callback(deactivate_muzzle_flash).set_delay(0.1)

func deactivate_muzzle_flash():
	if emitter:
		emitter.emitting = false

# Spawn tracer with collision detection using Area3D
func spawn_tracer_with_collision():
	if not tracer_scene:
		print("Warning: No tracer scene assigned!")
		return
	
	var model_node = get_parent()
	var start_position = model_node.global_position + model_node.global_transform.basis * muzzle_offset
	
	# TRY THESE OPTIONS - uncomment the one that works for your model orientation:
	
	# Option 1: Positive Z (remove the negative sign)
	var forward_direction = model_node.global_transform.basis.z
	
	# Option 2: If your model faces along X-axis
	# var forward_direction = model_node.global_transform.basis.x
	
	# Option 3: If your model faces along negative X-axis  
	# var forward_direction = -model_node.global_transform.basis.x
	
	# Option 4: If your model faces along Y-axis (unlikely but possible)
	# var forward_direction = model_node.global_transform.basis.y
	
	var end_position = start_position + forward_direction * tracer_max_distance
	
	# Create tracer with Area3D collision detection
	var tracer_projectile = create_tracer_with_area()
	get_tree().current_scene.add_child(tracer_projectile)
	tracer_projectile.global_position = start_position
	tracer_projectile.look_at(end_position, Vector3.UP)
	
	# Calculate travel time
	var travel_time = tracer_max_distance / tracer_speed
	
	# Animate movement
	var tween = create_tween()
	tween.tween_property(tracer_projectile, "global_position", end_position, travel_time)
	tween.tween_callback(cleanup_tracer.bind(tracer_projectile))

func create_tracer_with_area() -> Area3D:
	var area = Area3D.new()
	area.name = "TracerProjectile"
	
	# Create collision shape for detection
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.1, 0.1, 0.1)  # Small collision box
	collision_shape.shape = shape
	area.add_child(collision_shape)
	
	# Add visual (instantiate your tracer scene as child)
	if tracer_scene:
		var visual = tracer_scene.instantiate()
		area.add_child(visual)
	
	# Connect collision signals
	area.body_entered.connect(_on_tracer_hit_body.bind(area))
	area.area_entered.connect(_on_tracer_hit_area.bind(area))
	
	# Set collision detection to detect all bodies
	area.monitoring = true
	area.collision_layer = 0  # Don't be detected by others
	area.collision_mask = 1   # Detect default collision layer (adjust as needed)
	
	return area

func _on_tracer_hit_body(tracer: Area3D, body: Node3D):
	# Delete tracer immediately when hitting any body
	cleanup_tracer(tracer)

func _on_tracer_hit_area(tracer: Area3D, other_area: Area3D):
	# Delete tracer immediately when hitting any area
	cleanup_tracer(tracer)

func cleanup_tracer(tracer_instance: Node):
	if is_instance_valid(tracer_instance):
		tracer_instance.queue_free()
