extends Control
## Главное меню: Играть / Настройки / Выйти.

const GAME_SCENE := "res://scenes/test.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
const SettingsScript := preload("res://scripts/settings.gd")

@onready var play_button: Button = $Center/VBox/PlayButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var quit_button: Button = $Center/VBox/QuitButton


func _ready() -> void:
	SettingsScript.apply_saved(get_tree())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_settings_pressed() -> void:
	if has_node("Settings"):
		return
	add_child(SETTINGS_SCENE.instantiate())


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if has_node("Settings"):
		return
	if event.is_action_pressed("ui_accept"):
		_on_play_pressed()
