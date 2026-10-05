extends RefCounted
## Upscaling: the 3D world is drawn at a part of the screen's resolution and scaled up — the frame costs less on the
## card (with the 3D Earth of Pax CorpInc3D the most). What Godot has: FSR 1.0 (spatial, any renderer but the
## compatibility one), FSR 2.2 (temporal, Forward+ only), MetalFX (Apple, Metal). DLSS and XeSS are not in the engine:
## they need a native extension the game itself would ship; a mod cannot load one — listed in the window, switched off.
## Also the screen-space anti-aliasing (FXAA, SMAA) and TAA, which fit a lower resolution.
## The interface (2D) is never scaled: only the 3D view.

const MODES: Array[String] = ["off", "fsr1", "fsr2", "metalfx_spatial", "metalfx_temporal", "dlss", "xess"]
const SCALES: Array[float] = [1.0, 0.77, 0.67, 0.59, 0.5]   # native, quality, balanced, performance, ultra performance
const AA: Array[String] = ["game", "off", "fxaa", "smaa", "taa"]


## Whether the running renderer can do a mode.
static func available(mode: String) -> bool:
	var method := RenderingServer.get_current_rendering_method()
	match mode:
		"off":
			return true
		"fsr1":
			return method != "gl_compatibility"
		"fsr2":
			return method == "forward_plus"
		"metalfx_spatial", "metalfx_temporal":
			return OS.get_name() in ["macOS", "iOS"] and method != "gl_compatibility"
	return false   # dlss, xess: not in Godot


## Applies to the root viewport (the 3D world); remembers nothing — the caller keeps the settings.
static func apply(vp: Viewport, mode: String, scale: float, sharpness: float, aa: String) -> void:
	if vp == null:
		return
	var m := mode if available(mode) else "off"
	match m:
		"fsr1":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		"fsr2":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		"metalfx_spatial":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
		"metalfx_temporal":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0 if m == "off" else clampf(scale, 0.25, 1.0)
	# FSR's sharpening: 0 the sharpest, 2 none.
	vp.fsr_sharpness = clampf(2.0 - sharpness * 2.0, 0.0, 2.0)
	# Temporal upscalers bring their own anti-aliasing; a lower resolution blurs the textures' detail less with a bias.
	vp.texture_mipmap_bias = log(vp.scaling_3d_scale) / log(2.0) if m != "off" else 0.0
	match aa:
		"off":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false
		"fxaa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
		"smaa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			vp.use_taa = false
		"taa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = m != "fsr2" and m != "metalfx_temporal" and RenderingServer.get_current_rendering_method() != "gl_compatibility"


## How the root viewport is set now (to restore when the mod goes): [mode, scale, sharpness, mipmap bias, ssaa, taa].
static func snapshot(vp: Viewport) -> Array:
	return [vp.scaling_3d_mode, vp.scaling_3d_scale, vp.fsr_sharpness, vp.texture_mipmap_bias, vp.screen_space_aa, vp.use_taa]


static func restore(vp: Viewport, s: Array) -> void:
	if vp == null or s.size() < 6:
		return
	vp.scaling_3d_mode = s[0]
	vp.scaling_3d_scale = s[1]
	vp.fsr_sharpness = s[2]
	vp.texture_mipmap_bias = s[3]
	vp.screen_space_aa = s[4]
	vp.use_taa = s[5]
