extends Resource
class_name CombatUnitData

# Basic unit properties
@export var unit_icon: Texture2D
@export var unit_name: String = "Infantry"
@export var health: int = 100
@export var move_speed: float = 5.0
@export var cost: int = 50

# Combat properties
@export var weapon_type: String = "Rifle"
@export var abilities: Array[String] = []

# Squad configuration
@export_range(1, 10) var squad_size: int = 5

# Detection and engagement ranges
@export_range(5.0, 60.0, 1.0) var vision_range: float = 40.0
@export_range(1.0, 60.0, 1.0) var attack_range: float = 40.0

# Attack timing
@export_range(0.01, 10.0) var attack_interval: float = 5

# Formation settings
@export_range(1.0, 10.0, 0.5) var formation_spacing: float = 3.0
