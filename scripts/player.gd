extends CharacterBody3D

const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const STEP_SOUND := preload("res://resorses/audio/steps.mp3")

@export var speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

@export var stamina_max: float = 100.0
@export var stamina_drain: float = 25.0
@export var stamina_regen: float = 18.0
@export var stamina_regen_delay: float = 1.0

@export var walk_step_interval: float = 0.4
@export var sprint_step_interval: float = 0.28
@export var walk_pitch: float = 1.0
@export var sprint_pitch: float = 1.35

@onready var camera: Camera3D = $Camera3D

var stamina: float = 100.0
var is_sprinting: bool = false

var _pitch: float = 0.0
var _regen_cooldown: float = 0.0
var _stamina_bar: ProgressBar

var _step_player: AudioStreamPlayer
var _step_timer: float = 0.0

var _pause_menu: CanvasLayer


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = stamina_max
	camera.current = true
	# CSG-меш внутри игрока мешает FPS-обзору — прячем его,
	# коллизия (CollisionShape3D) при этом остаётся.
	if has_node("CSGCylinder3D"):
		($CSGCylinder3D as Node3D).visible = false
	_build_stamina_ui()
	_step_player = AudioStreamPlayer.new()
	_step_player.name = "Steps"
	_step_player.stream = STEP_SOUND
	add_child(_step_player)
	_pause_menu = PAUSE_MENU.instantiate()
	add_child(_pause_menu)


func _unhandled_input(event: InputEvent) -> void:
	# Esc теперь обрабатывает PauseMenu
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
	if get_tree().paused:
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
	_update_steps(delta, input_dir.length() > 0.1)


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


func _update_steps(delta: float, moving: bool) -> void:
	if _step_player == null:
		return
	if not moving or not is_on_floor():
		_step_timer = 0.0
		# Прыжок / остановка — обрываем звук шага сразу
		if _step_player.playing:
			_step_player.stop()
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if is_sprinting:
		_step_player.pitch_scale = sprint_pitch * randf_range(0.97, 1.03)
		_step_timer = sprint_step_interval
	else:
		_step_player.pitch_scale = walk_pitch * randf_range(0.97, 1.03)
		_step_timer = walk_step_interval
	_step_player.play()
