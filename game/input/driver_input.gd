class_name DriverInput
extends RefCounted


## Read once per physics tick. Future touch controls can drive the same InputMap actions.
## This is local input only; the server must validate and sequence network commands.
static func sample() -> Dictionary:
	return {
		"steering": Input.get_axis("drive_left", "drive_right"),
		"throttle": Input.get_action_strength("drive_accelerate"),
		"brake": Input.get_action_strength("drive_brake"),
		"drift": Input.is_action_pressed("drive_drift"),
		"use_item_1": Input.is_action_just_pressed("use_item_1"),
		"use_item_2": Input.is_action_just_pressed("use_item_2"),
		"look_back": Input.is_action_pressed("look_back"),
	}
