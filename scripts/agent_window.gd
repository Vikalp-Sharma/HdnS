## Agent Monitor Window — External OS window per agent.
## Top: Live first-person POV camera (what the agent sees in the actual world).
## Middle: Orbiting 3D showcase with yellow clearance ring.
## Bottom: Holographic thought terminal with Q-values and neural stats.
class_name AgentWindow
extends Window

const AgentBodyBuilder = preload("res://scripts/agent_body_builder.gd")

# ── Config ──
const ORBIT_SPEED: float = 0.6
const ORBIT_RADIUS: float = 2.8
const ORBIT_HEIGHT: float = 1.8
const RING_PULSE_SPEED: float = 2.0
const POV_FOV: float = 90.0

# ── Refs ──
var agent_ref: AIAgent
var _main_world: World3D

# POV viewport (shares main world)
var _pov_viewport: SubViewport
var _pov_camera: Camera3D

# Showcase viewport (own world)
var _showcase_viewport: SubViewport
var _showcase_camera: Camera3D
var _model_root: Node3D
var _clearance_ring: MeshInstance3D
var _clearance_ring_outer: MeshInstance3D

# UI
var _thoughts_label: RichTextLabel
var _title_lbl: RichTextLabel
var _pov_label: Label
var _character_body: Node3D
var _showcase_glow: OmniLight3D

# State
var _orbit_angle: float = 0.0
var _pulse_time: float = 0.0
var _agent_color: Color
var _is_hider: bool
var thought_data: Dictionary = {}


func setup(agent: AIAgent, win_title: String, win_pos: Vector2i, main_world: World3D = null) -> void:
	agent_ref = agent
	_main_world = main_world
	if _main_world == null and agent != null and agent.is_inside_tree() and agent.get_world_3d() != null:
		_main_world = agent.get_world_3d()
	_is_hider = agent.agent_type == AIAgent.AgentType.HIDER
	_agent_color = Color(0.3, 0.5, 1.0) if _is_hider else Color(1.0, 0.3, 0.2)

	title = win_title
	size = Vector2i(450, 800)
	position = win_pos
	transient = false
	always_on_top = false
	unresizable = false
	min_size = Vector2i(360, 600)

	close_requested.connect(_on_close)
	focus_entered.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	window_input.connect(func(_ev: InputEvent):
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	)
	_build_ui()
	_build_showcase_scene()
	update_role_appearance()


## Dynamically adapts window styling, titles, and 3D showcase model when agent roles swap.
func update_role_appearance() -> void:
	if agent_ref == null:
		return
	_is_hider = agent_ref.agent_type == AIAgent.AgentType.HIDER
	_agent_color = Color(0.3, 0.5, 1.0) if _is_hider else Color(1.0, 0.3, 0.2)
	var role_str: String = "HIDER" if _is_hider else "SEEKER"
	title = "◆ %s [%s] ◆" % [agent_ref.agent_name, role_str]

	if _title_lbl:
		var hex: String = _agent_color.to_html(false)
		_title_lbl.text = "[center][b][color=#%s]◆ %s — %s UNIT ◆[/color][/b][/center]" % [hex, agent_ref.agent_name.to_upper(), role_str]

	if _pov_label:
		_pov_label.text = "◉ LIVE POV — %s" % role_str
		_pov_label.add_theme_color_override("font_color", Color(_agent_color.r, _agent_color.g, _agent_color.b, 0.8))

	# Physically morph the 3D showcase character model to match the role!
	if _character_body:
		AgentBodyBuilder.build_body(_character_body, agent_ref.agent_type, true)

	if _showcase_glow:
		_showcase_glow.light_color = Color(0.2, 0.6, 1.0) if _is_hider else Color(1.0, 0.2, 0.15)
		_showcase_glow.light_energy = 0.9 if _is_hider else 1.3


func _on_close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or agent_ref == null:
		return

	# ── Update POV camera to follow agent ──
	if _pov_camera and is_instance_valid(agent_ref):
		if _pov_viewport.world_3d == null:
			if _main_world:
				_pov_viewport.world_3d = _main_world
			elif agent_ref.get_world_3d():
				_pov_viewport.world_3d = agent_ref.get_world_3d()

		var facing := Vector3(agent_ref.facing_dir.x, 0, agent_ref.facing_dir.y).normalized()
		if facing.length_squared() < 0.01:
			facing = Vector3(0, 0, -1)
		# Position at agent's eye level, slightly forward to avoid seeing own mesh
		var eye_pos: Vector3 = agent_ref.global_position + Vector3(0, 0.8, 0) + facing * 0.45
		_pov_camera.position = eye_pos
		_pov_camera.look_at(eye_pos + facing * 5.0, Vector3.UP)

	# ── Orbit showcase camera ──
	_orbit_angle += ORBIT_SPEED * delta
	if _showcase_camera:
		var cam_orbit_pos := Vector3(
			cos(_orbit_angle) * ORBIT_RADIUS,
			ORBIT_HEIGHT,
			sin(_orbit_angle) * ORBIT_RADIUS
		)
		_showcase_camera.position = cam_orbit_pos
		_showcase_camera.look_at_from_position(cam_orbit_pos, Vector3(0, 0.85, 0), Vector3.UP)

	# ── Rotate showcase model ──
	if _model_root:
		_model_root.rotation.y += 0.3 * delta

	# ── Pulse clearance rings ──
	_pulse_time += delta
	if _clearance_ring:
		var mat: StandardMaterial3D = _clearance_ring.material_override
		if mat:
			mat.albedo_color.a = 0.10 + 0.06 * sin(_pulse_time * RING_PULSE_SPEED)
	if _clearance_ring_outer:
		var mat2: StandardMaterial3D = _clearance_ring_outer.material_override
		if mat2:
			mat2.albedo_color.a = 0.05 + 0.04 * sin(_pulse_time * RING_PULSE_SPEED * 0.7 + 1.0)

	# ── Update thoughts display ──
	_refresh_thoughts()


func set_thought_data(data: Dictionary) -> void:
	thought_data = data


# ══════════════════════════════════════════════════════════════
#  UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	root.add_child(vbox)

	# ── 1. POV Viewport (top — agent's live first-person view) ──
	var pov_container := SubViewportContainer.new()
	pov_container.stretch = true
	pov_container.custom_minimum_size = Vector2(450, 240)
	pov_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pov_container.size_flags_stretch_ratio = 1.2
	vbox.add_child(pov_container)

	_pov_viewport = SubViewport.new()
	_pov_viewport.size = Vector2i(450, 240)
	_pov_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pov_viewport.msaa_3d = Viewport.MSAA_2X
	# Share the main game world so this camera sees the actual map + agents
	if _main_world:
		_pov_viewport.world_3d = _main_world
	pov_container.add_child(_pov_viewport)

	_pov_camera = Camera3D.new()
	_pov_camera.fov = POV_FOV
	_pov_camera.near = 0.1
	_pov_camera.far = 100.0
	_pov_camera.current = true
	_pov_viewport.add_child(_pov_camera)

	# POV label overlay
	_pov_label = Label.new()
	_pov_label.text = "◉ LIVE POV — %s" % ("HIDER" if _is_hider else "SEEKER")
	_pov_label.add_theme_font_size_override("font_size", 11)
	_pov_label.add_theme_color_override("font_color", Color(_agent_color.r, _agent_color.g, _agent_color.b, 0.8))
	_pov_label.position = Vector2(8, 4)
	pov_container.add_child(_pov_label)

	# ── Separator ──
	var sep := _make_separator(_agent_color, 3)
	vbox.add_child(sep)

	# ── 2. Title bar ──
	var title_panel := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	ts.content_margin_left = 12
	ts.content_margin_right = 12
	ts.content_margin_top = 5
	ts.content_margin_bottom = 5
	title_panel.add_theme_stylebox_override("panel", ts)
	vbox.add_child(title_panel)

	_title_lbl = RichTextLabel.new()
	_title_lbl.bbcode_enabled = true
	_title_lbl.fit_content = true
	_title_lbl.scroll_active = false
	var hex: String = _agent_color.to_html(false)
	var role: String = "HIDER UNIT" if _is_hider else "SEEKER UNIT"
	var a_name: String = agent_ref.agent_name.to_upper() if agent_ref else "AGENT"
	_title_lbl.text = "[center][b][color=#%s]◆ %s — %s ◆[/color][/b][/center]" % [hex, a_name, role]
	_title_lbl.add_theme_font_size_override("normal_font_size", 15)
	_title_lbl.add_theme_font_size_override("bold_font_size", 17)
	title_panel.add_child(_title_lbl)

	# ── 3. Showcase viewport (orbiting model) ──
	var showcase_container := SubViewportContainer.new()
	showcase_container.stretch = true
	showcase_container.custom_minimum_size = Vector2(450, 180)
	showcase_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	showcase_container.size_flags_stretch_ratio = 0.8
	vbox.add_child(showcase_container)

	_showcase_viewport = SubViewport.new()
	_showcase_viewport.size = Vector2i(450, 180)
	_showcase_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_showcase_viewport.msaa_3d = Viewport.MSAA_2X
	showcase_container.add_child(_showcase_viewport)

	# ── Separator ──
	vbox.add_child(_make_separator(_agent_color, 2))

	# ── 4. Thoughts panel ──
	var thoughts_panel := PanelContainer.new()
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color(0.02, 0.03, 0.05, 0.95)
	tp.border_width_left = 1
	tp.border_width_right = 1
	tp.border_width_bottom = 1
	tp.border_color = Color(_agent_color.r * 0.3, _agent_color.g * 0.3, _agent_color.b * 0.3, 0.5)
	tp.content_margin_left = 12
	tp.content_margin_right = 12
	tp.content_margin_top = 8
	tp.content_margin_bottom = 8
	thoughts_panel.add_theme_stylebox_override("panel", tp)
	thoughts_panel.custom_minimum_size = Vector2(450, 260)
	thoughts_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thoughts_panel.size_flags_stretch_ratio = 1.0
	vbox.add_child(thoughts_panel)

	_thoughts_label = RichTextLabel.new()
	_thoughts_label.bbcode_enabled = true
	_thoughts_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thoughts_label.scroll_active = true
	_thoughts_label.add_theme_font_size_override("normal_font_size", 13)
	_thoughts_label.add_theme_font_size_override("bold_font_size", 14)
	thoughts_panel.add_child(_thoughts_label)


func _make_separator(color: Color, height: int) -> PanelContainer:
	var sep := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.85)
	sep.add_theme_stylebox_override("panel", ss)
	sep.custom_minimum_size = Vector2(0, height)
	return sep


# ══════════════════════════════════════════════════════════════
#  3D SHOWCASE SCENE
# ══════════════════════════════════════════════════════════════

func _build_showcase_scene() -> void:
	# Private World3D for showcase to isolate model and lighting
	_showcase_viewport.own_world_3d = true

	# Showcase environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.14, 0.20)
	env.ambient_light_energy = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.0

	var we := WorldEnvironment.new()
	we.environment = env
	_showcase_viewport.add_child(we)

	# Orbiting camera
	_showcase_camera = Camera3D.new()
	var cam_pos := Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0)
	_showcase_camera.position = cam_pos
	_showcase_camera.look_at_from_position(cam_pos, Vector3(0, 0.85, 0), Vector3.UP)
	_showcase_camera.current = true
	_showcase_viewport.add_child(_showcase_camera)

	# Lighting
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.85, 0.90, 1.0)
	key_light.light_energy = 1.0
	key_light.shadow_enabled = true
	key_light.shadow_bias = 0.02
	key_light.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	_showcase_viewport.add_child(key_light)

	var rim := DirectionalLight3D.new()
	rim.light_color = _agent_color
	rim.light_energy = 0.75
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-145), 0)
	_showcase_viewport.add_child(rim)

	# Model root
	_model_root = Node3D.new()
	_showcase_viewport.add_child(_model_root)

	# Procedural character body container
	_character_body = Node3D.new()
	_character_body.name = "CharacterBody"
	_model_root.add_child(_character_body)
	var initial_role: int = agent_ref.agent_type if agent_ref else (AIAgent.AgentType.HIDER if _is_hider else AIAgent.AgentType.SEEKER)
	AgentBodyBuilder.build_body(_character_body, initial_role, true)

	# Agent glow
	_showcase_glow = OmniLight3D.new()
	_showcase_glow.light_color = Color(0.2, 0.7, 1.0) if _is_hider else Color(1.0, 0.22, 0.15)
	_showcase_glow.light_energy = 1.2 if _is_hider else 1.6
	_showcase_glow.omni_range = 5.0
	_showcase_glow.omni_attenuation = 1.3
	_showcase_glow.position = Vector3(0, 1.5, 0)
	_model_root.add_child(_showcase_glow)

	# ── Yellow clearance rings ──
	_clearance_ring = _make_ring(1.8, 0.03, Color(1.0, 0.92, 0.3, 0.12))
	_clearance_ring.position = Vector3(0, 0.05, 0)
	_model_root.add_child(_clearance_ring)

	_clearance_ring_outer = _make_ring(2.5, 0.02, Color(1.0, 0.85, 0.2, 0.06))
	_clearance_ring_outer.position = Vector3(0, 0.03, 0)
	_model_root.add_child(_clearance_ring_outer)

	# Hex platform
	var plat := MeshInstance3D.new()
	var plat_m := CylinderMesh.new()
	plat_m.top_radius = 3.0
	plat_m.bottom_radius = 3.2
	plat_m.height = 0.1
	plat_m.radial_segments = 6
	plat.mesh = plat_m
	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.06, 0.06, 0.09)
	plat_mat.roughness = 0.9
	plat.material_override = plat_mat
	plat.position = Vector3(0, -0.05, 0)
	_showcase_viewport.add_child(plat)

	# Grid lines
	_build_grid_lines()


func _make_ring(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 48
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


func _build_grid_lines() -> void:
	var im := ImmediateMesh.new()
	var c := Color(0.15, 0.2, 0.3, 0.25)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for ring_i in range(1, 5):
		var r: float = ring_i * 0.8
		var segs: int = 32
		for s in range(segs):
			var a1: float = TAU * s / segs
			var a2: float = TAU * (s + 1) / segs
			im.surface_set_color(c)
			im.surface_add_vertex(Vector3(cos(a1) * r, 0.02, sin(a1) * r))
			im.surface_set_color(c)
			im.surface_add_vertex(Vector3(cos(a2) * r, 0.02, sin(a2) * r))
	for i in range(8):
		var a: float = TAU * i / 8.0
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(0, 0.02, 0))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(cos(a) * 3.5, 0.02, sin(a) * 3.5))
	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	_showcase_viewport.add_child(mi)


# ══════════════════════════════════════════════════════════════
#  THOUGHTS DISPLAY
# ══════════════════════════════════════════════════════════════

func _refresh_thoughts() -> void:
	if _thoughts_label == null:
		return
	if thought_data.is_empty():
		_thoughts_label.text = "[color=#334455]◌ Awaiting neural link...[/color]"
		return

	var dim := "#556677"
	var bright := "#88ddff"
	var warn := "#ff8844"
	var good := "#44ff88"
	var accent: String = _agent_color.to_html(false)
	var t := ""

	# Agent Identity & Active Role
	var agent_name_str: String = thought_data.get("agent_name", ("Agent 1" if _is_hider else "Agent 2"))
	var role_name_str: String = thought_data.get("role_name", ("HIDER" if _is_hider else "SEEKER"))
	var score_val: int = thought_data.get("score", 0)
	var wins_val: int = thought_data.get("match_wins", 0)
	var losses_val: int = thought_data.get("match_losses", 0)
	var role_col: String = "#55aaff" if role_name_str == "HIDER" else "#ff5544"

	t += "[color=#%s]▸ UNIT:[/color] [b]%s[/b]  [color=#%s]│[/color]  [color=#%s]ROLE:[/color] [b][color=%s]%s[/color][/b]\n" % [
		dim, agent_name_str.to_upper(), dim, dim, role_col, role_name_str]
	t += "[color=#%s]▸ MATCH SCORE:[/color] [b][color=#ffff55]%d PTS[/color][/b]  [color=#%s](%dW - %dL)[/color]\n" % [
		dim, score_val, dim, wins_val, losses_val]

	# Tactical Status
	var status: String = thought_data.get("status", "IDLE")
	var sc: String = good if ("PURSUING" in status or "EVADING" in status or "INVESTIGATING" in status or "SWEEPING" in status or "COVER" in status) else (warn if "CORNERED" in status else bright)
	t += "[color=#%s]▸ STATUS:[/color] [b][color=%s]%s[/color][/b]\n" % [dim, sc, status]

	# Action
	t += "[color=#%s]▸ ACTION:[/color] [b]%s[/b]\n" % [dim, thought_data.get("action_name", "—")]

	# Target
	var sees: bool = thought_data.get("sees_opponent", false)
	var opp: String = "SEEKER" if _is_hider else "HIDER"
	if sees:
		t += "[color=#%s]▸ TARGET:[/color] [color=#%s]⚠ %s DETECTED (%.1f)[/color]\n" % [
			dim, warn, opp, thought_data.get("opponent_dist", 0.0)]
	else:
		t += "[color=#%s]▸ TARGET:[/color] [color=#%s]%s not visible[/color]\n" % [dim, dim, opp]

	t += "\n"

	# Q-Values
	t += "[color=#%s]┌─ DECISION MATRIX ──────────┐[/color]\n" % accent
	var qv: Array = thought_data.get("q_values", [0, 0, 0, 0, 0])
	var names: Array = ["↑ NORTH", "↓ SOUTH", "← WEST ", "→ EAST ", "● HOLD "]
	var la: int = thought_data.get("last_action", -1)

	var q_abs_max: float = 0.001
	for v in qv:
		q_abs_max = maxf(q_abs_max, absf(v))

	for i in range(mini(qv.size(), 5)):
		var bar_len: int = clampi(int(absf(qv[i]) / q_abs_max * 12), 0, 12)
		var bar := _repeat_char("█", bar_len) + _repeat_char("░", 12 - bar_len)
		var lc: String = bright if i == la else dim
		var bc: String = accent if qv[i] >= 0 else warn
		var marker: String = " ◀" if i == la else ""
		t += "[color=#%s]│[/color] [color=#%s]%s[/color] [color=#%s]%s[/color] [color=#%s]%+.1f[/color]%s\n" % [
			accent, lc, names[i], bc, bar, lc, qv[i], marker]

	t += "[color=#%s]└────────────────────────────┘[/color]\n\n" % accent

	# Neural Core
	t += "[color=#%s]┌─ NEURAL CORE ──────────────┐[/color]\n" % accent
	var eps: float = thought_data.get("epsilon", 1.0)
	var er: float = thought_data.get("episode_reward", 0.0)
	var ar: float = thought_data.get("avg_reward", 0.0)
	var al: float = thought_data.get("avg_loss", 0.0)
	var st: int = thought_data.get("total_steps", 0)

	t += "[color=#%s]│[/color] [color=#%s]Exploration:[/color]  %.4f\n" % [accent, dim, eps]
	t += "[color=#%s]│[/color] [color=#%s]Ep Reward :[/color]  [color=#%s]%+.1f[/color]\n" % [
		accent, dim, good if er > 0 else warn, er]
	t += "[color=#%s]│[/color] [color=#%s]Avg Reward:[/color]  %+.1f\n" % [accent, dim, ar]
	t += "[color=#%s]│[/color] [color=#%s]Avg Loss  :[/color]  %.5f\n" % [accent, dim, al]
	t += "[color=#%s]│[/color] [color=#%s]Steps     :[/color]  %d\n" % [accent, dim, st]
	t += "[color=#%s]└────────────────────────────┘[/color]" % accent

	_thoughts_label.text = t


func _repeat_char(c: String, count: int) -> String:
	var s := ""
	for _i in range(maxi(0, count)):
		s += c
	return s
