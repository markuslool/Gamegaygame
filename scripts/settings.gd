extends CanvasLayer
## Настройки: громкость, разрешение (определяется из системы),
## режим окна, масштаб интерфейса, VSync. Правится в scenes/settings.tscn.

const SAVE_PATH := "user://settings.cfg"

# Кандидаты 4:3 / 16:10 / 16:9 — в список попадут только те,
# что реально влезут в экран системы (+ родное разрешение экрана).
const BASE_MODES: Array[Vector2i] = [
	Vector2i(640, 480),
	Vector2i(800, 600),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1280, 960),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1600, 1200),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const MODES: Array[DisplayServer.WindowMode] = [
	DisplayServer.WINDOW_MODE_WINDOWED,
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]
const MODE_NAMES: PackedStringArray = ["Оконный", "Полный экран", "Эксклюзивный"]

const ASPECTS: Array[Window.ContentScaleAspect] = [
	Window.CONTENT_SCALE_ASPECT_EXPAND,
	Window.CONTENT_SCALE_ASPECT_KEEP,
	Window.CONTENT_SCALE_ASPECT_IGNORE,
]
const ASPECT_NAMES: PackedStringArray = [
	"Расширить (без полос)",
	"Сохранить (чёрные полосы)",
	"Растянуть (искажение)",
]

const MSAA_MODES: Array[Viewport.MSAA] = [
	Viewport.MSAA_DISABLED,
	Viewport.MSAA_2X,
	Viewport.MSAA_4X,
	Viewport.MSAA_8X,
]

# Один выбор = готовый пресет (индекс MSAA, FXAA, TAA)
const AA_NAMES: PackedStringArray = [
	"Выкл",
	"FXAA (быстро)",
	"MSAA 2×",
	"MSAA 4×",
	"MSAA 4× + FXAA",
	"MSAA 8×",
	"TAA",
	"TAA + FXAA",
]
const AA_MSAA: Array = [0, 0, 1, 2, 2, 3, 0, 0]
const AA_FXAA: Array = [false, true, false, false, true, false, false, true]
const AA_TAA: Array = [false, false, false, false, false, false, true, true]

const UPSCALERS: Array[Viewport.Scaling3DMode] = [
	Viewport.SCALING_3D_MODE_BILINEAR,
	Viewport.SCALING_3D_MODE_FSR,
	Viewport.SCALING_3D_MODE_FSR2,
]
const UPSCALER_NAMES: PackedStringArray = ["Билинейный", "FSR 1.0", "FSR 2.2"]

@onready var screen_label: Label = %ScreenLabel
@onready var vol_slider: HSlider = %VolSlider
@onready var vol_label: Label = %VolLabel
@onready var res_options: OptionButton = %ResOptions
@onready var mode_options: OptionButton = %ModeOptions
@onready var aspect_options: OptionButton = %AspectOptions
@onready var vsync_check: CheckButton = %VSync
@onready var aa_options: OptionButton = %AA
@onready var upscaler_options: OptionButton = %Upscaler
@onready var render_scale_slider: HSlider = %RenderScale
@onready var render_scale_label: Label = %RenderScaleLabel
@onready var sharp_slider: HSlider = %SharpSlider
@onready var sharp_label: Label = %SharpLabel
@onready var back_button: Button = %BackButton

var _resolutions_cache: Array[Vector2i] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var scr := DisplayServer.screen_get_size()
	var hz := int(DisplayServer.screen_get_refresh_rate())
	if hz > 0:
		screen_label.text = "Экран: %d × %d · %d Гц" % [scr.x, scr.y, hz]
	else:
		screen_label.text = "Экран: %d × %d" % [scr.x, scr.y]

	_resolutions_cache = system_resolutions()
	for i in _resolutions_cache.size():
		var s := _resolutions_cache[i]
		var mark := " ★" if s == scr else ""
		res_options.add_item("%d × %d · %s%s" % [s.x, s.y, aspect_name(s), mark])
	for n in MODE_NAMES:
		mode_options.add_item(n)
	for n in ASPECT_NAMES:
		aspect_options.add_item(n)
	for n in AA_NAMES:
		aa_options.add_item(n)
	for n in UPSCALER_NAMES:
		upscaler_options.add_item(n)

	var cfg := _load_cfg()
	vol_slider.set_value_no_signal(float(cfg.get_value("audio", "volume", 80.0)))
	vol_label.text = "Громкость: %d%%" % int(vol_slider.value)
	res_options.select(_saved_resolution_idx(cfg))
	mode_options.select(clampi(int(cfg.get_value("video", "window_mode", 0)), 0, MODES.size() - 1))
	aspect_options.select(_saved_aspect_idx(cfg))
	vsync_check.set_pressed_no_signal(bool(cfg.get_value("video", "vsync", true)))
	aa_options.select(_saved_aa_idx(cfg))
	upscaler_options.select(clampi(int(cfg.get_value("video", "upscaler", 0)), 0, UPSCALERS.size() - 1))
	render_scale_slider.set_value_no_signal(float(cfg.get_value("video", "render_scale", 100.0)))
	render_scale_label.text = "Масштаб рендера: %d%%" % int(render_scale_slider.value)
	sharp_slider.set_value_no_signal(float(cfg.get_value("video", "fsr_sharpness", 90.0)))
	sharp_label.text = "Резкость FSR: %d%%" % int(sharp_slider.value)

	vol_slider.value_changed.connect(_on_volume_changed)
	res_options.item_selected.connect(_on_video_changed.unbind(1))
	mode_options.item_selected.connect(_on_video_changed.unbind(1))
	aspect_options.item_selected.connect(_on_video_changed.unbind(1))
	vsync_check.toggled.connect(_on_video_changed.unbind(1))
	aa_options.item_selected.connect(_on_video_changed.unbind(1))
	upscaler_options.item_selected.connect(_on_video_changed.unbind(1))
	render_scale_slider.value_changed.connect(_on_render_scale_changed)
	sharp_slider.value_changed.connect(_on_sharp_changed)
	back_button.pressed.connect(close)

	_apply_all()
	back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	queue_free()


static func apply_saved(tree: SceneTree) -> void:
	var cfg := _load_cfg()
	_apply_audio(float(cfg.get_value("audio", "volume", 80.0)))
	_apply_video(
		tree,
		_saved_size(cfg),
		clampi(int(cfg.get_value("video", "window_mode", 0)), 0, MODES.size() - 1),
		_saved_aspect_idx(cfg),
		bool(cfg.get_value("video", "vsync", true))
	)
	_apply_render(
		tree.root,
		_saved_aa_idx(cfg),
		clampi(int(cfg.get_value("video", "upscaler", 0)), 0, UPSCALERS.size() - 1),
		float(cfg.get_value("video", "render_scale", 100.0)),
		float(cfg.get_value("video", "fsr_sharpness", 90.0))
	)


static func system_resolutions() -> Array[Vector2i]:
	var scr := DisplayServer.screen_get_size()
	var list: Array[Vector2i] = []
	for m in BASE_MODES:
		if m.x <= scr.x and m.y <= scr.y and not list.has(m):
			list.append(m)
	if not list.has(scr):
		list.append(scr)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	if list.is_empty():
		list.append(Vector2i(1280, 720))
	return list


static func aspect_name(s: Vector2i) -> String:
	var r := float(s.x) / float(maxi(s.y, 1))
	if absf(r - 16.0 / 9.0) < 0.03:
		return "16:9"
	if absf(r - 16.0 / 10.0) < 0.03:
		return "16:10"
	if absf(r - 4.0 / 3.0) < 0.03:
		return "4:3"
	if absf(r - 21.0 / 9.0) < 0.05:
		return "21:9"
	if absf(r - 5.0 / 4.0) < 0.03:
		return "5:4"
	if absf(r - 3.0 / 2.0) < 0.03:
		return "3:2"
	var g := _gcd(s.x, s.y)
	return "%d:%d" % [s.x / g, s.y / g]


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return maxi(a, 1)


func _saved_resolution_idx(cfg: ConfigFile) -> int:
	var want := _saved_size(cfg)
	var best := 0
	var best_diff := 99999999
	for i in _resolutions_cache.size():
		if _resolutions_cache[i] == want:
			return i
		var d := absi(_resolutions_cache[i].x - want.x) + absi(_resolutions_cache[i].y - want.y)
		if d < best_diff:
			best_diff = d
			best = i
	return best


static func _saved_size(cfg: ConfigFile) -> Vector2i:
	var s := str(cfg.get_value("video", "resolution_size", ""))
	if s.contains("x"):
		var p := s.split("x")
		if p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int():
			return Vector2i(p[0].to_int(), p[1].to_int())
	var cur := DisplayServer.window_get_size()
	var best := cur
	var best_diff := 99999999
	for m in system_resolutions():
		var d := absi(m.x - cur.x) + absi(m.y - cur.y)
		if d < best_diff:
			best_diff = d
			best = m
	return best


static func _saved_aspect_idx(cfg: ConfigFile) -> int:
	var saved := int(cfg.get_value("video", "aspect", -1))
	if saved >= 0 and saved < ASPECTS.size():
		return saved
	return 0


# Старый сейв хранит msaa/fxaa/taa по отдельности — маппим на пресет.
# Точного совпадения может не быть — тогда подбираем по MSAA+TAA.
static func _saved_aa_idx(cfg: ConfigFile) -> int:
	if cfg.has_section_key("video", "aa_preset"):
		return clampi(int(cfg.get_value("video", "aa_preset", 0)), 0, AA_NAMES.size() - 1)
	var msaa := clampi(int(cfg.get_value("video", "msaa3d", 0)), 0, MSAA_MODES.size() - 1)
	var fxaa := bool(cfg.get_value("video", "fxaa", false))
	var taa := bool(cfg.get_value("video", "taa", false))
	for i in AA_NAMES.size():
		if int(AA_MSAA[i]) == msaa and bool(AA_FXAA[i]) == fxaa and bool(AA_TAA[i]) == taa:
			return i
	for i in AA_NAMES.size():
		if int(AA_MSAA[i]) == msaa and bool(AA_TAA[i]) == taa:
			return i
	return 0


func _apply_all() -> void:
	_apply_audio(vol_slider.value)
	_apply_video(get_tree(), _resolutions_cache[res_options.selected], mode_options.selected, aspect_options.selected, vsync_check.button_pressed)
	_apply_render(get_viewport(), aa_options.selected, upscaler_options.selected, render_scale_slider.value, sharp_slider.value)
	_save()


func _on_volume_changed(value: float) -> void:
	vol_label.text = "Громкость: %d%%" % int(value)
	_apply_audio(value)
	_save()


func _on_render_scale_changed(value: float) -> void:
	render_scale_label.text = "Масштаб рендера: %d%%" % int(value)
	_apply_all()


func _on_sharp_changed(value: float) -> void:
	sharp_label.text = "Резкость FSR: %d%%" % int(value)
	_apply_all()


func _on_video_changed() -> void:
	_apply_all()


static func _apply_audio(volume: float) -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, volume <= 0.0)
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(volume / 100.0, 0.0001)))


static func _apply_render(vp: Viewport, aa_idx: int, upscaler_idx: int, render_scale: float, sharpness: float) -> void:
	if vp == null:
		return
	var a := clampi(aa_idx, 0, AA_NAMES.size() - 1)
	vp.msaa_3d = MSAA_MODES[int(AA_MSAA[a])]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(AA_FXAA[a]) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(AA_TAA[a])
	vp.scaling_3d_mode = UPSCALERS[clampi(upscaler_idx, 0, UPSCALERS.size() - 1)]
	vp.scaling_3d_scale = clampf(render_scale / 100.0, 0.25, 2.0)
	# В движке инверсия: 0.0 — макс. резкость, 2.0 — минимум. Дефолт 0.2.
	vp.fsr_sharpness = clampf((100.0 - sharpness) / 100.0 * 2.0, 0.0, 2.0)


static func _apply_video(tree: SceneTree, size: Vector2i, mode_idx: int, aspect_idx: int, vsync: bool) -> void:
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_mode(MODES[clampi(mode_idx, 0, MODES.size() - 1)])
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	var root: Window = tree.root
	if root != null:
		root.content_scale_aspect = ASPECTS[clampi(aspect_idx, 0, ASPECTS.size() - 1)]
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var scr_idx := DisplayServer.window_get_current_screen()
		var rect := DisplayServer.screen_get_usable_rect(scr_idx)
		DisplayServer.window_set_position(rect.position + (rect.size - size) / 2)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", vol_slider.value)
	var s := _resolutions_cache[res_options.selected]
	cfg.set_value("video", "resolution_size", "%dx%d" % [s.x, s.y])
	cfg.set_value("video", "window_mode", mode_options.selected)
	cfg.set_value("video", "aspect", aspect_options.selected)
	cfg.set_value("video", "vsync", vsync_check.button_pressed)
	cfg.set_value("video", "aa_preset", aa_options.selected)
	cfg.set_value("video", "upscaler", upscaler_options.selected)
	cfg.set_value("video", "render_scale", render_scale_slider.value)
	cfg.set_value("video", "fsr_sharpness", sharp_slider.value)
	cfg.save(SAVE_PATH)


static func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg
