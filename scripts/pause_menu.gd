extends CanvasLayer
## Меню паузы. Редактируется в scenes/pause_menu.tscn.
## Esc — открыть/закрыть. Ставит игру на паузу.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")

var is_open: bool = false

@onready var resume_button: Button = %ResumeButton
@onready var menu_button: Button = %MenuButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	# Чтобы Esc и кнопки работали в паузе
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_open = false
	resume_button.pressed.connect(close)
	menu_button.pressed.connect(_quit_to_menu)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(_quit_game)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if has_node("Settings"):
			return
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	get_tree().paused = false
	is_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _open_settings() -> void:
	if has_node("Settings"):
		return
	add_child(SETTINGS_SCENE.instantiate())


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
