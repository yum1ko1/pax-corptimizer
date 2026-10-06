extends Node
## «Детали по дальности» (setting «lod»: off | normal | strong): the farther the camera from the planet it looks at, the
## coarser the textures and the models the engine draws — far away nobody sees the fine detail, and it is what the
## video card reads and draws every frame.
##   textures — the root viewport's texture_mipmap_bias grows with the distance (+½ a mip level normal, +1 strong): the
##     planet's maps, the buildings', the clouds' are read from smaller mip levels (+1/+2 blurred the clouds away and
##     the sea's relief into black);
##   models — left to Pax CorpInc3D's own levels (MESH below);
## near the ground (under near_r Earth radii from the centre) — as the game has it; full from far_r on.
## The bias the upscaler sets (upscale.gd: by its scale) is kept: ours is added on top and taken off again; when
## someone else changes the bias, that becomes the base.

const MODES := ["off", "normal", "strong"]
const BIAS := {"off": 0.0, "normal": 0.5, "strong": 1.0}
## The models' threshold is no longer raised: the mods' models have no in-between levels — the engine took the last,
## a few triangles, and the buildings looked removed from afar. Pax CorpInc3D draws its own levels (models → blocks).
const MESH := {"off": 1.0, "normal": 1.0, "strong": 1.0}

var mode := "normal"
var near_r := 1.15
var far_r := 2.5
var now_share := 0.0               # how far it is now (0 near … 1 far), for the panel
var _base_bias := 0.0
var _written_bias := INF
var _base_mesh := -1.0
var _written_mesh := INF
var _t := 0.0


func _ready() -> void:
	name = "Lod"
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_mode(m: String) -> void:
	mode = m if m in MODES else "normal"
	_t = 0.0
	if mode == "off":
		restore()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or mode == "off":
		return
	_t = 0.25
	var vp := get_viewport()
	if vp == null:
		return
	var f := _far_share()
	now_share = f
	# Someone else (the upscaler, the game) set the bias since our last write: that is the base now.
	if absf(vp.texture_mipmap_bias - _written_bias) > 0.0001:
		_base_bias = vp.texture_mipmap_bias
	if _base_mesh < 0.0 or absf(vp.mesh_lod_threshold - _written_mesh) > 0.0001:
		_base_mesh = vp.mesh_lod_threshold
	_written_bias = _base_bias + float(BIAS[mode]) * f
	_written_mesh = _base_mesh * lerpf(1.0, float(MESH[mode]), f)
	vp.texture_mipmap_bias = _written_bias
	vp.mesh_lod_threshold = _written_mesh


## 0 with the camera near the planet in view, 1 far from it (by its radius); 0 with no world.
func _far_share() -> float:
	var g: PaxGame = Pax.game
	if g == null or not is_instance_valid(g.main):
		return 0.0
	var cam := g.camera()
	var body := g.body_node(g.focused_body())
	if cam == null or body == null or not is_instance_valid(body):
		return 0.0
	var r := maxf(body.global_transform.basis.get_scale().x, 1e-6)
	var d := cam.global_position.distance_to(body.global_position) / r
	return smoothstep(near_r, far_r, d)


## The viewport as it was before us (the mod unloaded or the setting off).
func restore() -> void:
	var vp := get_viewport() if is_inside_tree() else null
	if vp == null:
		return
	if absf(vp.texture_mipmap_bias - _written_bias) <= 0.0001:
		vp.texture_mipmap_bias = _base_bias
	if _base_mesh >= 0.0 and absf(vp.mesh_lod_threshold - _written_mesh) <= 0.0001:
		vp.mesh_lod_threshold = _base_mesh
	_written_bias = INF
	_written_mesh = INF
	now_share = 0.0


func _exit_tree() -> void:
	restore()
