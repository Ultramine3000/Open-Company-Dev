extends Node3D

@onready var raycast: RayCast3D = $RayCast3D

func _ready():
	# Make sure raycast is enabled and updated
	raycast.enabled = true
	raycast.force_raycast_update()

func _physics_process(_delta: float) -> void:
	raycast.force_raycast_update()  # ensure raycast state is current

	if raycast.is_colliding():
		print("Ray hit:", raycast.get_collider())
		queue_free()
