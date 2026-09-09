extends CharacterBody3D

const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const STEP_SOUND := preload("res://resorses/audio/steps.mp3")
const GameSettings := preload("res://scripts/settings.gd")

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

## Реестр предметов: id -> {имя, сколько стамины даёт, макс. в рюкзаке}.
const ITEM_DEFS := {
	"soda": {"name": "Газировка", "stamina": 50.0, "max": 5},
}

@onready var camera: Camera3D = $Camera3D

var stamina: float = 100.0
var is_sprinting: bool = false

## Инвентарь: id -> количество.
var inventory: Dictionary = {}
var _inv_label: Label
var _notice := ""
var _notice_time := 0.0

var _pitch: float = 0.0
var _regen_cooldown: float = 0.0
var _stamina_bar: ProgressBar
var _invert_y := false

var _step_player: AudioStreamPlayer
var _step_timer: float = 0.0

var _pause_menu: CanvasLayer


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = stamina_max
	# Настройки из меню (чувствительность, инверсия, FOV, пост-эффекты сцены).
	mouse_sensitivity = GameSettings.get_mouse_sensitivity()
	_invert_y = GameSettings.get_invert_y()
	camera.fov = GameSettings.get_camera_fov()
	GameSettings.apply_post_fx(get_tree())
	camera.current = true
	# CSG-меш внутри игрока мешает FPS-обзору — прячем его,
	# коллизия (CollisionShape3D) при этом остаётся.
	if has_node("CSGCylinder3D"):
		($CSGCylinder3D as Node3D).visible = false
	_build_stamina_ui()
	_build_inventory_ui()
	_step_player = AudioStreamPlayer.new()
	_step_player.name = "Steps"
	_step_player.stream = STEP_SOUND
	add_child(_step_player)
	_pause_menu = PAUSE_MENU.instantiate()
	add_child(_pause_menu)


func _unhandled_input(event: InputEvent) -> void:
	# Esc теперь обрабатывает PauseMenu
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			add_item("soda")
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_E:
			use_item("soda")
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sensitivity)
		var dy := mm.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch + dy if _invert_y else _pitch - dy, -1.4, 1.4)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_notice = ""
			_update_inventory_ui()

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


func add_item(item_id: String, amount: int = 1) -> int:
	if not ITEM_DEFS.has(item_id):
		return 0
	var def: Dictionary = ITEM_DEFS[item_id]
	var max_n := int(def["max"])
	var cur := int(inventory.get(item_id, 0))
	var can := mini(amount, max_n - cur)
	if can <= 0:
		_notify("Рюкзак полон: %s (макс. %d)" % [str(def["name"]), max_n])
		return 0
	inventory[item_id] = cur + can
	_notify("+%d %s" % [can, str(def["name"])])
	_update_inventory_ui()
	return can


func use_item(item_id: String) -> bool:
	if not ITEM_DEFS.has(item_id):
		return false
	var def: Dictionary = ITEM_DEFS[item_id]
	var cur := int(inventory.get(item_id, 0))
	if cur <= 0:
		_notify("Нет газировки! Жми P, чтобы взять.")
		_update_inventory_ui()
		return false
	inventory[item_id] = cur - 1
	stamina = minf(stamina + float(def["stamina"]), stamina_max)
	_update_stamina_ui()
	_notify("Выпил газировку: +стамина")
	_update_inventory_ui()
	return true


func _build_inventory_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InventoryHUD"
	layer.layer = 5
	add_child(layer)

	_inv_label = Label.new()
	_inv_label.name = "InventoryLabel"
	_inv_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_inv_label.offset_left = 12.0
	_inv_label.offset_top = 12.0
	_inv_label.offset_right = 400.0
	_inv_label.offset_bottom = 140.0
	_inv_label.add_theme_font_size_override("font_size", 18)
	_inv_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_inv_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_inv_label)
	_update_inventory_ui()


func _update_inventory_ui() -> void:
	if _inv_label == null:
		return
	var lines: Array[String] = ["Инвентарь:"]
	for id in ITEM_DEFS.keys():
		lines.append("%s x%d" % [str(ITEM_DEFS[id]["name"]), int(inventory.get(id, 0))])
	lines.append("[P] взять газировку  [E] выпить (+50)")
	if _notice_time > 0.0 and not _notice.is_empty():
		lines.append(_notice)
	_inv_label.text = "\n".join(lines)


func _notify(text: String, time: float = 2.0) -> void:
	_notice = text
	_notice_time = time
	_update_inventory_ui()


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
