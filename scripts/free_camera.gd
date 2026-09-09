extends Camera3D
## Свободная камера: WASD + мышь (зажать ПКМ) + колесо = скорость.
## Минимум без настроек Input Map — работает из коробки.

@export var move_speed: float = 10.0
@export var fast_multiplier: float = 3.0
@export var sensitivity: float = 0.003
@export var invert_y: bool = false

var _pitch: float = -0.4
var _yaw: float = 0.0
var _rotating: bool = false


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			move_speed = clampf(move_speed * 1.1, 1.0, 100.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			move_speed = clampf(move_speed / 1.1, 1.0, 100.0)
	elif event is InputEventMouseMotion and _rotating:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * sensitivity
		var dy: float = mm.relative.y * sensitivity
		_pitch += dy if invert_y else -dy
		_pitch = clampf(_pitch, -1.55, 1.55)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.y = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	input_dir.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	# Стрелки — дублируют WASD
	if Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	input_dir = input_dir.limit_length(1.0)

	var up_down: float = float(Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL))

	var speed: float = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var basis_yaw := Basis(Vector3.UP, _yaw)
	var forward: Vector3 = -basis_yaw.z
	var right: Vector3 = basis_yaw.x

	var velocity: Vector3 = (right * input_dir.x - forward * input_dir.y) * speed
	velocity += Vector3.UP * up_down * speed
	position += velocity * delta
