class_name RoomBackdrop
extends Control
## Das Hinterzimmer als lebendiger, weichgezeichneter Hintergrund für Weg, Shop,
## Ergebnis usw. Die Kamera driftet langsam; optional sitzt ein Gegner am Tisch.
## Einfach als erstes Kind in eine 2D-Szene legen und ggf. `opponent` setzen.

const SHADER := preload("res://ui/blur_backdrop.gdshader")

## Gestalt am Tisch (leer = niemand).
var opponent: OpponentData
## 0 = scharf, ~3 = stark weichgezeichnet
var blur := 2.2
var darken := 0.5
## Kamera (Position, Blickziel) – Standard: von schräg hinten über den Tisch
var cam_from := Vector3(-0.55, 1.45, 1.05)
var cam_to := Vector3(0.05, 0.95, -0.35)

var world: TableWorld
var _view: SubViewportContainer
var _vp: SubViewport
var _t := 0.0
var _base: Transform3D


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_view = SubViewportContainer.new()
	_view.mouse_filter = MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("darken", darken)
	_view.material = mat
	add_child(_view)
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.add_child(_vp)
	world = TableWorld.new()
	_vp.add_child(world)
	world.build_room(opponent, true)
	world.sway_strength = 0.0
	world.camera.look_at_from_position(cam_from, cam_to)
	_base = world.camera.transform
	world.set_camera_pose(_base)
	_fit()
	get_viewport().size_changed.connect(_fit)


func _fit() -> void:
	# halbe Auflösung reicht – das Bild wird ohnehin weichgezeichnet
	UIKit.fit_viewport(self, _view, _vp, 0.5 if blur > 0.5 else 1.0)


func _process(delta: float) -> void:
	_t += delta
	if world == null:
		return
	var drift := Transform3D(Basis.from_euler(Vector3(sin(_t * 0.13) * 0.025, sin(_t * 0.09) * 0.05, 0)),
		Vector3(sin(_t * 0.11) * 0.03, sin(_t * 0.17) * 0.012, 0))
	world.set_camera_pose(_base * drift)
