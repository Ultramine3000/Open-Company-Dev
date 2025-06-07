extends Node

# References to sibling nodes
@onready var animation_player: AnimationPlayer
@onready var audio_player: AudioStreamPlayer3D

# Dictionary to map animation names to audio file paths
var animation_sounds = {
	"Fire": "res://data/sfx/gunshot_sfx.mp3"
	# Add more animation-sound pairs here as needed
}

# Preloaded audio resources for better performance
var audio_resources = {}

# Track current animation to detect changes
var current_animation = ""
var was_playing = false

func _ready():
	# Find sibling nodes by searching parent's children
	var parent = get_parent()
	if not parent:
		print("Error: No parent node found!")
		return
	
	# Find AnimationPlayer sibling
	for child in parent.get_children():
		if child is AnimationPlayer:
			animation_player = child
			break
	
	# Find AudioPlayer3D sibling  
	for child in parent.get_children():
		if child is AudioStreamPlayer3D:
			audio_player = child
			break
	
	# Verify nodes exist
	if not animation_player:
		print("Error: AnimationPlayer sibling not found!")
		return
		
	if not audio_player:
		print("Error: AudioPlayer3D sibling not found!")
		return
	
	print("Found AnimationPlayer: ", animation_player.name)
	print("Found AudioPlayer3D: ", audio_player.name)
	
	# Preload audio resources
	preload_audio_resources()

func _process(_delta):
	# Check if animation player exists and is playing
	if not animation_player:
		return
		
	var is_playing = animation_player.is_playing()
	var anim_name = animation_player.current_animation
	
	# Detect when a new animation starts
	if is_playing and (not was_playing or current_animation != anim_name):
		current_animation = anim_name
		play_sound_for_animation(anim_name)
	
	# Update tracking variables
	was_playing = is_playing
	if not is_playing:
		current_animation = ""

func preload_audio_resources():
	"""Preload all audio files for better performance"""
	for anim_name in animation_sounds:
		var audio_path = animation_sounds[anim_name]
		if ResourceLoader.exists(audio_path):
			audio_resources[anim_name] = load(audio_path)
			print("Loaded audio for animation: ", anim_name)
		else:
			print("Warning: Audio file not found: ", audio_path)

func play_sound_for_animation(anim_name: String):
	"""Play the corresponding sound effect for the given animation"""
	if anim_name in animation_sounds:
		if anim_name in audio_resources:
			audio_player.stream = audio_resources[anim_name]
			audio_player.play()
			print("Playing sound for animation: ", anim_name)
		else:
			print("Warning: Audio resource not loaded for animation: ", anim_name)
	else:
		print("No sound mapped for animation: ", anim_name)

func add_animation_sound(anim_name: String, audio_path: String):
	"""Add a new animation-sound mapping at runtime"""
	animation_sounds[anim_name] = audio_path
	if ResourceLoader.exists(audio_path):
		audio_resources[anim_name] = load(audio_path)
		print("Added new animation sound: ", anim_name, " -> ", audio_path)
	else:
		print("Warning: Audio file not found when adding: ", audio_path)

func remove_animation_sound(anim_name: String):
	"""Remove an animation-sound mapping"""
	if anim_name in animation_sounds:
		animation_sounds.erase(anim_name)
		audio_resources.erase(anim_name)
		print("Removed animation sound: ", anim_name)
