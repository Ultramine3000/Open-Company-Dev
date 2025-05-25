extends Node

@onready var animation_player: AnimationPlayer
@onready var emitter: GPUParticles3D

var tracer_scene: PackedScene
var tracer_speed: float = 200.0
var tracer_max_distance: float = 100.0
var muzzle_offset: Vector3 = Vector3.ZERO

func _ready():
	animation_player = get_parent().get_node("AnimationPlayer")
	tracer_scene = preload("res://scenes/tracer.tscn")
	emitter = get_child(0)
	if emitter:
		emitter.emitting = false
	
	if animation_player.has_signal("animation_started"):
		animation_player.animation_started.connect(_on_animation_started)
	else:
		animation_player.animation_changed.connect(_on_animation_changed)

func _on_animation_started(animation_name: String):
	if animation_name == "Fire":
		await get_tree().create_timer(0.05).timeout
		if animation_player.current_animation == "Fire":
			activate_muzzle_flash()
			spawn_tracer_with_collision()

func _on_animation_changed():
	if animation_player.current_animation == "Fire" and animation_player.is_playing() and animation_player.current_animation != "Move":
		activate_muzzle_flash()
		spawn_tracer_with_collision()

func activate_muzzle_flash():
	if emitter:
		emitter.emitting = true
		create_tween().tween_callback(deactivate_muzzle_flash).set_delay(0.1)

func deactivate_muzzle_flash():
	if emitter:
		emitter.emitting = false

func spawn_tracer_with_collision():
	if not tracer_scene:
		return
	
	var model_node = get_parent()
	var start_position = model_node.global_position + model_node.global_transform.basis * muzzle_offset
	var forward_direction = model_node.global_transform.basis.z
	var end_position = start_position + forward_direction * tracer_max_distance
	
	var tracer_projectile = create_tracer_with_area()
	get_tree().current_scene.add_child(tracer_projectile)
	tracer_projectile.global_position = start_position
	tracer_projectile.look_at(end_position, Vector3.UP)
	
	var travel_time = tracer_max_distance / tracer_speed
	var tween = create_tween()
	tween.tween_property(tracer_projectile, "global_position", end_position, travel_time)
	tween.tween_callback(cleanup_tracer.bind(tracer_projectile))

func create_tracer_with_area() -> Area3D:
	var area = Area3D.new()
	area.name = "TracerProjectile"
	
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.1, 0.1, 0.1)
	collision_shape.shape = shape
	area.add_child(collision_shape)
	
	if tracer_scene:
		var visual = tracer_scene.instantiate()
		area.add_child(visual)
	
	area.body_entered.connect(_on_tracer_hit_body)
	area.area_entered.connect(_on_tracer_hit_area)
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1
	
	return area

func _on_tracer_hit_body(body: Node3D):
	var tracer = get_parent_tracer(self)
	cleanup_tracer(tracer)

func _on_tracer_hit_area(other_area: Area3D):
	var tracer = get_parent_tracer(self)
	cleanup_tracer(tracer)

func get_parent_tracer(node: Node) -> Node:
	while node and not node.name == "TracerProjectile":
		node = node.get_parent()
	return node

func cleanup_tracer(tracer_instance: Node):
	if is_instance_valid(tracer_instance):
		tracer_instance.queue_free()
