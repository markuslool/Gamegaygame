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

## Прыжок «с весом»: сильнее тянет вниз при падении и при раннем отпускании Space.
@export var fall_gravity_mult: float = 1.7
@export var low_jump_mult: float = 2.2

## Покачивание камеры при ходьбе.
@export var head_bob_enabled := true
@export var head_bob_amount := 1.0

@export var walk_step_interval: float = 0.4
@export var sprint_step_interval: float = 0.28
@export var walk_pitch: float = 1.0
@export var sprint_pitch: float = 1.35

## Реестр предметов: id -> {имя, сколько стамины даёт, размер стака}.
const ITEM_DEFS := {
	"soda": {"name": "Газировка", "stamina": 50.0, "stack": 16},
}
const HOTBAR_SIZE := 5

@onready var camera: Camera3D = $Camera3D

var stamina: float = 100.0
var is_sprinting: bool = false

## Хотбар как в Майнкрафте: слоты (null или {id, count}), выбранный слот.
var slots: Array = []
var selected := 0
var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []
var _hint_label: Label
var _hand_root: Node3D
var _soda_icon: Texture2D
var _notice := ""
var _notice_time := 0.0

var _pitch: float = 0.0
var _regen_cooldown: float = 0.0
var _stamina_bar: ProgressBar
var _invert_y := false
var _bob_phase := 0.0
var _bob_strength := 0.0
var _cam_base := Vector3.ZERO

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
	_cam_base = camera.position
	# CSG-меш внутри игрока мешает FPS-обзору — прячем его,
	# коллизия (CollisionShape3D) при этом остаётся.
	if has_node("CSGCylinder3D"):
		($CSGCylinder3D as Node3D).visible = false
	_build_stamina_ui()
	_build_inventory_ui()
	_build_hand_can()
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
			use_selected()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			select_slot(int(event.keycode) - int(KEY_1))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			select_slot(posmod(selected - 1, HOTBAR_SIZE))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			select_slot(posmod(selected + 1, HOTBAR_SIZE))
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

	# Гравитация с весом: падение быстрее взлёта,
	# ранний отпуск Space обрезает прыжок.
	var jump_held := Input.is_key_pressed(KEY_SPACE)
	if not is_on_floor():
		var g := get_gravity()
		if velocity.y < 0.0:
			g *= fall_gravity_mult
		elif not jump_held:
			g *= low_jump_mult
		velocity += g * delta

	# Прыжок
	if jump_held and is_on_floor():
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

	# Покачивание камеры: фаза от скорости, затухание на месте.
	if head_bob_enabled:
		var hspeed := Vector2(velocity.x, velocity.z).length()
		var moving := hspeed > 0.5 and is_on_floor()
		_bob_strength = move_toward(_bob_strength, 1.0 if moving else 0.0, delta * (6.0 if moving else 4.0))
		if _bob_strength > 0.001:
			_bob_phase += delta * (4.0 + hspeed * 1.1)
			var off := Vector3(sin(_bob_phase) * 0.035, -absf(cos(_bob_phase)) * 0.03, 0.0) * _bob_strength * head_bob_amount
			camera.position = _cam_base + off
		elif camera.position != _cam_base:
			camera.position = _cam_base


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
	var stack_max := int(ITEM_DEFS[item_id]["stack"])
	var left := amount
	# Сначала добиваем существующие стаки, потом пустые слоты.
	for i in slots.size():
		if left <= 0:
			break
		var s = slots[i]
		if s != null and str(s["id"]) == item_id and int(s["count"]) < stack_max:
			var can := mini(left, stack_max - int(s["count"]))
			s["count"] = int(s["count"]) + can
			left -= can
	for i in slots.size():
		if left <= 0:
			break
		if slots[i] == null:
			var can := mini(left, stack_max)
			slots[i] = {"id": item_id, "count": can}
			left -= can
	var got := amount - left
	if got > 0:
		_notify("+%d %s" % [got, str(ITEM_DEFS[item_id]["name"])])
	else:
		_notify("Нет места! Выпей что-нибудь (E).")
	_update_inventory_ui()
	return got


func use_selected() -> bool:
	var s = slots[selected]
	if s == null or str(s["id"]) != "soda":
		# Ищем соду в любом слоте и переключаемся на неё.
		for i in slots.size():
			var o = slots[i]
			if o != null and str(o["id"]) == "soda":
				select_slot(i)
				return use_selected()
		_notify("Нет газировки! Жми P, чтобы взять.")
		_update_inventory_ui()
		return false
	return use_item("soda")


func use_item(item_id: String) -> bool:
	var s = slots[selected]
	if s == null or str(s["id"]) != item_id:
		return false
	s["count"] = int(s["count"]) - 1
	if int(s["count"]) <= 0:
		slots[selected] = null
	stamina = minf(stamina + float(ITEM_DEFS[item_id]["stamina"]), stamina_max)
	_update_stamina_ui()
	_notify("Выпил газировку: +стамина")
	_update_inventory_ui()
	_update_hand()
	return true


func select_slot(i: int) -> void:
	selected = clampi(i, 0, HOTBAR_SIZE - 1)
	_update_inventory_ui()
	_update_hand()


func _make_soda_icon() -> Texture2D:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8, 28):
		for x in range(10, 22):
			img.set_pixel(x, y, Color(0.85, 0.15, 0.2))
	for y in range(9, 27):
		img.set_pixel(12, y, Color(1.0, 0.55, 0.55))
		img.set_pixel(13, y, Color(1.0, 0.55, 0.55))
	for x in range(11, 21):
		for y in [6, 7, 28, 29]:
			img.set_pixel(x, y, Color(0.8, 0.8, 0.85))
	img.set_pixel(16, 7, Color(0.4, 0.4, 0.45))
	return ImageTexture.create_from_image(img)


func _slot_stylebox(sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = Color(1, 0.9, 0.3) if sel else Color(0.5, 0.5, 0.5, 0.8)
	sb.set_border_width_all(3 if sel else 1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


func _build_inventory_ui() -> void:
	slots.clear()
	for i in HOTBAR_SIZE:
		slots.append(null)
	_soda_icon = _make_soda_icon()

	var layer := CanvasLayer.new()
	layer.name = "InventoryHUD"
	layer.layer = 5
	add_child(layer)

	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -150.0
	bar.offset_right = 150.0
	bar.offset_top = -172.0
	bar.offset_bottom = -116.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	layer.add_child(bar)

	_slot_panels.clear()
	_slot_icons.clear()
	_slot_counts.clear()
	for i in HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(52, 52)
		panel.add_theme_stylebox_override("panel", _slot_stylebox(i == selected))
		bar.add_child(panel)
		_slot_panels.append(panel)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		_slot_icons.append(icon)

		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 12)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		num.set_anchors_preset(Control.PRESET_TOP_LEFT)
		num.offset_left = 3.0
		num.offset_top = 1.0
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		var count := Label.new()
		count.add_theme_font_size_override("font_size", 16)
		count.add_theme_color_override("font_color", Color(1, 1, 1))
		count.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		count.add_theme_constant_override("outline_size", 4)
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -26.0
		count.offset_top = -24.0
		count.offset_right = -3.0
		count.offset_bottom = -3.0
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count)
		_slot_counts.append(count)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.anchor_left = 0.5
	_hint_label.anchor_right = 0.5
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -300.0
	_hint_label.offset_right = 300.0
	_hint_label.offset_top = -114.0
	_hint_label.offset_bottom = -52.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hint_label)
	_update_inventory_ui()


func _update_inventory_ui() -> void:
	if _hint_label == null:
		return
	for i in HOTBAR_SIZE:
		_slot_panels[i].add_theme_stylebox_override("panel", _slot_stylebox(i == selected))
		var s = slots[i]
		if s != null and str(s["id"]) == "soda":
			_slot_icons[i].texture = _soda_icon
			_slot_counts[i].text = str(int(s["count"]))
		else:
			_slot_icons[i].texture = null
			_slot_counts[i].text = ""
	var lines: Array[String] = ["[1-5/колесо] выбор  [P] взять  [E] выпить"]
	if _notice_time > 0.0 and not _notice.is_empty():
		lines.append(_notice)
	_hint_label.text = "\n".join(lines)


func _notify(text: String, time: float = 2.0) -> void:
	_notice = text
	_notice_time = time
	_update_inventory_ui()


func _build_hand_can() -> void:
	_hand_root = Node3D.new()
	_hand_root.name = "HandCan"
	_hand_root.position = Vector3(0.35, -0.32, -0.7)
	camera.add_child(_hand_root)

	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.2)
	red.roughness = 0.35
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.8, 0.8, 0.85)
	silver.metallic = 0.8
	silver.roughness = 0.3

	var body := MeshInstance3D.new()
	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = 0.035
	can_mesh.bottom_radius = 0.035
	can_mesh.height = 0.12
	can_mesh.radial_segments = 16
	body.mesh = can_mesh
	body.material_override = red
	_hand_root.add_child(body)

	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.036
	lid_mesh.bottom_radius = 0.036
	lid_mesh.height = 0.012
	lid_mesh.radial_segments = 16
	lid.mesh = lid_mesh
	lid.material_override = silver
	lid.position = Vector3(0, 0.062, 0)
	_hand_root.add_child(lid)

	_hand_root.rotation_degrees = Vector3(-12, -18, 6)
	_update_hand()


func _update_hand() -> void:
	if _hand_root == null:
		return
	var s = slots[selected] if selected < slots.size() else null
	_hand_root.visible = s != null and str(s["id"]) == "soda"


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
