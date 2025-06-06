extends Node

@onready var animation_player: AnimationPlayer
@onready var emitter: GPUParticles3D
var tracer_scene: PackedScene
var tracer_speed: float = 200.0
var tracer_max_distance: float = 200.0
var muzzle_offset: Vector3 = Vector3.ZERO

func _ready():
	animation_player = get_parent().get_node_or_null("AnimationPlayer")
	tracer_scene = preload("res://scenes/tracer.tscn")
	emitter = get_child(0)
	
	if emitter:
		emitter.emitting = false
	
	# Connect to animation signals
	if animation_player:
		if animation_player.has_signal("animation_started"):
			animation_player.animation_started.connect(_on_animation_started)
		else:
			animation_player.animation_changed.connect(_on_animation_changed)

func _on_animation_started(animation_name: String):
	if animation_name == "Fire" or animation_name == "Crouch_Fire":
		await get_tree().create_timer(0.05).timeout
		if animation_player and animation_player.current_animation == animation_name:
			fire_effects()

func _on_animation_changed():
	if not animation_player:
		return
		
	var current_anim = animation_player.current_animation
	if (current_anim == "Fire" or current_anim == "Crouch_Fire") and animation_player.is_playing():
		fire_effects()

func fire_effects():
	activate_muzzle_flash()
	spawn_tracer()

func activate_muzzle_flash():
	if emitter:
		emitter.emitting = true
		create_tween().tween_callback(deactivate_muzzle_flash).set_delay(0.1)

func deactivate_muzzle_flash():
	if emitter:
		emitter.emitting = false

func spawn_tracer():
	if not tracer_scene:
		return
	
	var model_node = get_parent()
	if not model_node or not is_instance_valid(model_node):
		return
	
	var start_position = model_node.global_position + model_node.global_transform.basis * muzzle_offset
	var forward_direction = model_node.global_transform.basis.z
	var end_position = start_position + forward_direction * tracer_max_distance
	
	var tracer = tracer_scene.instantiate()
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = start_position
	tracer.look_at(end_position, Vector3.UP)
	
	var travel_time = tracer_max_distance / tracer_speed
	var tween = create_tween()
	tween.tween_property(tracer, "global_position", end_position, travel_time)
