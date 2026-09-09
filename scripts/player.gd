extends CharacterBody3D
## Скрипт для твоего ручного player (CharacterBody3D).
## Гравитация + коллизия (move_and_slide) + WASD + прыжок + мышь.
## Клик — захват мыши, Esc — освободить.

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	# CSG-меш внутри игрока мешает FPS-обзору — прячем его,
	# коллизия (CollisionShape3D) при этом остаётся.
	if has_node("CSGCylinder3D"):
		($CSGCylinder3D as VisualInstance3D).set_layer_mask_value(1, false)
		($CSGCylinder3D as Node3D).visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
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

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() if input_dir.length() > 0.01 else Vector3.ZERO
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta * 10.0)

	move_and_slide()
