extends CharacterBody3D

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@export var speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

@export var stamina_max: float = 100.0
@export var stamina_drain: float = 25.0
@export var stamina_regen: float = 18.0
@export var stamina_regen_delay: float = 1.0

@onready var camera: Camera3D = $Camera3D

var stamina: float = 100.0
var is_sprinting: bool = false

var _pitch: float = 0.0
var _regen_cooldown: float = 0.0
var _stamina_bar: ProgressBar

var _paused: bool = false
var _pause_layer: CanvasLayer
var _resume_button: Button


func _ready() -> void:
	# Нужен ALWAYS чтобы Esc работал и в паузе
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = stamina_max
	camera.current = true
	# CSG-меш внутри игрока мешает FPS-обзору — прячем его,
	# коллизия (CollisionShape3D) при этом остаётся.
	if has_node("CSGCylinder3D"):
		($CSGCylinder3D as Node3D).visible = false
	_build_stamina_ui()
	_build_pause_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if _paused:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if _paused:
		return

	# Гравитация
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Прыжок
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	# Движение относительно поворота игрока
	var input_dir := Vector2.ZERO
	input_dir.y = float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	input_dir.x = float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	input_dir = input_dir.limit_length(1.0)

	# Бег на Shift: только при движении и пока есть стамина
	var want_sprint: bool = Input.is_key_pressed(KEY_SHIFT) and input_dir.length() > 0.1 and stamina > 0.0
	if want_sprint:
		is_sprinting = true
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		_regen_cooldown = stamina_regen_delay
	else:
		is_sprinting = false
		_regen_cooldown -= delta
		if _regen_cooldown <= 0.0:
			stamina = minf(stamina + stamina_regen * delta, stamina_max)

	var current_speed: float = sprint_speed if is_sprinting else speed
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, current_speed * delta * 10.0)

	move_and_slide()
	_update_stamina_ui()


func _build_stamina_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StaminaHUD"
	add_child(layer)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.name = "StaminaBar"
	_stamina_bar.min_value = 0.0
	_stamina_bar.max_value = stamina_max
	_stamina_bar.value = stamina
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(300, 18)
	# Низ по центру экрана
	_stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bar.anchor_left = 0.5
	_stamina_bar.anchor_right = 0.5
	_stamina_bar.anchor_top = 1.0
	_stamina_bar.anchor_bottom = 1.0
	_stamina_bar.offset_left = -150.0
	_stamina_bar.offset_right = 150.0
	_stamina_bar.offset_top = -48.0
	_stamina_bar.offset_bottom = -30.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(9)
	_stamina_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.8, 0.35, 1)
	fill.set_corner_radius_all(9)
	_stamina_bar.add_theme_stylebox_override("fill", fill)

	layer.add_child(_stamina_bar)


func _update_stamina_ui() -> void:
	if _stamina_bar == null:
		return
	_stamina_bar.value = stamina
	# Краснеет когда пустеет
	var fill := _stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = Color(0.9, 0.25, 0.2, 1) if stamina < 25.0 else Color(0.25, 0.8, 0.35, 1)


func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseMenu"
	_pause_layer.layer = 10
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Esc — продолжить"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	hint.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hint)

	_resume_button = Button.new()
	_resume_button.name = "ResumeButton"
	_resume_button.text = "Продолжить"
	_resume_button.custom_minimum_size = Vector2(260, 48)
	_resume_button.add_theme_font_size_override("font_size", 22)
	_resume_button.pressed.connect(_resume_game)
	vbox.add_child(_resume_button)

	var menu_button := Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "В главное меню"
	menu_button.custom_minimum_size = Vector2(260, 48)
	menu_button.add_theme_font_size_override("font_size", 22)
	menu_button.pressed.connect(_quit_to_menu)
	vbox.add_child(menu_button)

	var quit_button := Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "Выйти из игры"
	quit_button.custom_minimum_size = Vector2(260, 44)
	quit_button.add_theme_font_size_override("font_size", 18)
	quit_button.pressed.connect(_quit_game)
	vbox.add_child(quit_button)


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	_pause_layer.visible = _paused
	if _paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _resume_game() -> void:
	if _paused:
		_toggle_pause()


func _quit_to_menu() -> void:
	get_tree().paused = false
	_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
