extends Node
## Autoload „Settings“: Optionen für Grafik, Audio und Allgemeines.
## Wird in user://settings.cfg gespeichert und beim Start angewendet.
## Szenen mit 3D-Ansicht hören auf `changed` und rufen apply_viewport/apply_environment.

signal changed

const PATH := "user://settings.cfg"

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum Quality { LOW, MEDIUM, HIGH }
enum Speed { SLOW, NORMAL, FAST }

const WINDOW_MODE_NAMES := ["Fenster", "Randloses Vollbild", "Vollbild"]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160),
]
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 165, 240] # 0 = unbegrenzt
const MSAA_NAMES := ["Aus", "2×", "4×", "8×"]
const MSAA_VALUES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const QUALITY_NAMES := ["Niedrig", "Mittel", "Hoch"]
const SPEED_NAMES := ["Gemütlich", "Normal", "Schnell"]
const SHADOW_ATLAS := [0, 2048, 4096]

## Erhöhen, wenn sich Audio-Standardwerte ändern: ältere Einstellungsdateien übernehmen
## dann einmalig die neue Musiklautstärke (sonst bliebe der alte gespeicherte Wert).
const AUDIO_VERSION := 2

## Standardwerte: [Abschnitt, Schlüssel] → Wert
const DEFAULTS := {
	"graphics/window_mode": WindowMode.WINDOWED,
	"graphics/resolution": 0,
	"graphics/vsync": true,
	"graphics/fps_limit": 0,
	"graphics/msaa": 1,
	"graphics/render_scale": 1.0,
	"graphics/shadows": Quality.HIGH,
	"graphics/glow": true,
	"graphics/brightness": 1.0,
	"audio/master": 0.8,
	"audio/music": 0.2, # Musik bewusst leise (≈ 20 %)
	"audio/sfx": 0.8,
	"audio/mute_unfocused": true,
	"audio/version": AUDIO_VERSION,
	"general/ai_speed": Speed.NORMAL,
	"general/anim_speed": Speed.NORMAL,
	"general/camera_sway": true,
	"general/messages": true,
	"general/ui_scale": 1.0,
}

var _values := {}
var _focused := true


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply_all()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			_apply_audio()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_apply_audio()


# --- Werte ----------------------------------------------------------------------

func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	apply_all()
	save_settings()
	changed.emit()


func reset_section(section: String) -> void:
	for key: String in DEFAULTS:
		if key.begins_with(section + "/"):
			_values[key] = DEFAULTS[key]
	apply_all()
	save_settings()
	changed.emit()


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(PATH) or cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/")
		if cfg.has_section_key(parts[0], parts[1]):
			var v: Variant = cfg.get_value(parts[0], parts[1])
			if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
				_values[key] = v
	if int(cfg.get_value("audio", "version", 1)) < AUDIO_VERSION:
		_values["audio/music"] = DEFAULTS["audio/music"]
		_values["audio/version"] = AUDIO_VERSION
		save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		var parts := key.split("/")
		cfg.set_value(parts[0], parts[1], _values[key])
	cfg.save(PATH)


# --- Abfragen für das Spiel ------------------------------------------------------

## Faktor für die Bedenkzeit der Gegner.
func ai_delay_factor() -> float:
	return [1.5, 1.0, 0.45][get_value("general/ai_speed")]


## Faktor für Kartenanimationen (kleiner = schneller).
func anim_time_factor() -> float:
	return [1.35, 1.0, 0.6][get_value("general/anim_speed")]


func camera_sway() -> bool:
	return get_value("general/camera_sway")


func show_messages() -> bool:
	return get_value("general/messages")


func shadows_enabled() -> bool:
	return get_value("graphics/shadows") != Quality.LOW


# --- Anwenden -------------------------------------------------------------------

func apply_all() -> void:
	_apply_window()
	_apply_audio()
	Engine.max_fps = FPS_LIMITS[clampi(get_value("graphics/fps_limit"), 0, FPS_LIMITS.size() - 1)]
	var root := get_tree().root if get_tree() != null else null
	if root != null:
		root.content_scale_factor = get_value("general/ui_scale")


## Für SubViewports mit 3D-Inhalt (Kantenglättung, Renderauflösung, Schatten).
func apply_viewport(vp: SubViewport) -> void:
	if vp == null:
		return
	vp.msaa_3d = MSAA_VALUES[clampi(get_value("graphics/msaa"), 0, 3)]
	vp.scaling_3d_scale = get_value("graphics/render_scale")
	vp.positional_shadow_atlas_size = SHADOW_ATLAS[get_value("graphics/shadows")] if shadows_enabled() else 0


## Für die WorldEnvironment der 3D-Szene (Leuchten, Helligkeit).
func apply_environment(env: Environment, base_exposure: float) -> void:
	if env == null:
		return
	env.glow_enabled = get_value("graphics/glow")
	env.tonemap_exposure = base_exposure * float(get_value("graphics/brightness"))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = get_value("graphics/window_mode")
	var vsync: bool = get_value("graphics/vsync")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			var was_windowed := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := RESOLUTIONS[clampi(get_value("graphics/resolution"), 0, RESOLUTIONS.size() - 1)]
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
			if DisplayServer.window_get_size() != size or not was_windowed:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _apply_audio() -> void:
	var mute: bool = not _focused and get_value("audio/mute_unfocused")
	_set_bus("Master", 0.0 if mute else get_value("audio/master"))
	_set_bus("Music", get_value("audio/music"))
	_set_bus("SFX", get_value("audio/sfx"))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Musik- und Effekt-Busse anlegen, falls das Bus-Layout fehlt.
func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
