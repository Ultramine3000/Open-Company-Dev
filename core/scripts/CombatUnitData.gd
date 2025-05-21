extends Resource
class_name CombatUnitData

@export var unit_icon: Texture2D
@export var unit_name: String
@export var health: int
@export var move_speed: float
@export var cost: int
@export var weapon_type: String
@export var abilities: Array[String]
@export_range(4, 7) var squad_size: int = 5
