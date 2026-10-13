## HUD overlay displaying RL training stats, Q-value heatmap, and controls.
class_name GameHUD
extends CanvasLayer

var _stats_panel: PanelContainer
var _stats_label: RichTextLabel
var _heatmap_panel: Control
var _controls_label: Label
var _timer_panel: PanelContainer
var _timer_label: RichTextLabel
var _visible: bool = true

# Banner state for round results
var _banner_timer: float = 0.0
var _banner_text: String = ""

# Cached data for heatmap
var _wall_grid: Array = []
var _q_value_grid: Array = []  # 2D array of max Q-values per tile
var _grid_width: int = 40
var _grid_height: int = 40
var _hider_pos: Vector2i = Vector2i(-1, -1)
var _seeker_pos: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	layer = 10
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_visible = !_visible
		_stats_panel.visible = _visible
		_heatmap_panel.visible = _visible
		_controls_label.visible = _visible
		_timer_panel.visible = _visible


## Update all HUD elements with current game state.
func update_stats(data: Dictionary) -> void:
	# Update Top-Centre Round Timer
	var time_left: float = data.get("time_left", 180.0)
	var max_time: float = data.get("max_time", 180.0)
	var mins: int = int(time_left) / 60
	var secs: int = int(time_left) % 60

	if _timer_label:
		if _banner_timer > 0.0:
			_banner_timer = maxf(0.0, _banner_timer - 0.25)
			_timer_label.text = _banner_text
		else:
			var time_color: String = "#55ddff"
			var icon: String = "⏱"
			if time_left <= 30.0:
				time_color = "#ff4444"
				icon = "⚠"
			elif time_left <= 60.0:
				time_color = "#ffbb33"
				icon = "⏳"

			var timer_bbcode := "[center][font_size=10][color=#88aacc]ROUND TIME REMAINING[/color][/font_size]\n[b][font_size=24][color=%s]%s %02d:%02d[/color][/font_size][/b][/center]" % [time_color, icon, mins, secs]
			_timer_label.text = timer_bbcode

	var text := ""
	text += "[b]═══ HIDE & SEEK RL ═══[/b]\n\n"

	# Episode & Time info
	text += "[color=yellow]Episode:[/color] %d\n" % data.get("episode", 0)
	text += "[color=yellow]Time Left:[/color] %02d:%02d / %02d:00\n" % [mins, secs, int(max_time) / 60]
	text += "[color=yellow]Turns Taken:[/color] %d\n" % data.get("turn", 0)
	text += "[color=yellow]Speed:[/color] %dx\n\n" % data.get("speed", 1)

	# Agents stats & match records
	var a1: Dictionary = data.get("agent1", {})
	var a2: Dictionary = data.get("agent2", {})
	var a1_role: String = a1.get("role", "HIDER")
	var a2_role: String = a2.get("role", "SEEKER")
	var a1_color: String = "cornflowerblue" if a1_role == "HIDER" else "tomato"
	var a2_color: String = "cornflowerblue" if a2_role == "HIDER" else "tomato"

	# Agent 1
	text += "[color=%s]── %s [%s] ──[/color]\n" % [a1_color, a1.get("name", "Agent 1"), a1_role]
	text += "  Score: %d PTS  (W:%d | L:%d)\n" % [a1.get("score", 0), a1.get("wins", 0), a1.get("losses", 0)]
	var a1_st: Dictionary = a1.get("stats", {})
	text += "  ε: %.4f | Ep Rew: %.1f\n" % [a1_st.get("epsilon", 1.0), a1_st.get("episode_reward", 0.0)]
	text += "  Avg Rew: %.1f | Loss: %.5f\n\n" % [a1_st.get("avg_reward", 0.0), a1_st.get("avg_loss", 0.0)]

	# Agent 2
	text += "[color=%s]── %s [%s] ──[/color]\n" % [a2_color, a2.get("name", "Agent 2"), a2_role]
	text += "  Score: %d PTS  (W:%d | L:%d)\n" % [a2.get("score", 0), a2.get("wins", 0), a2.get("losses", 0)]
	var a2_st: Dictionary = a2.get("stats", {})
	text += "  ε: %.4f | Ep Rew: %.1f\n" % [a2_st.get("epsilon", 1.0), a2_st.get("episode_reward", 0.0)]
	text += "  Avg Rew: %.1f | Loss: %.5f\n\n" % [a2_st.get("avg_reward", 0.0), a2_st.get("avg_loss", 0.0)]

	# Head-to-head match comparison
	var a1_w: int = a1.get("wins", 0)
	var a2_w: int = a2.get("wins", 0)
	var tot_w: int = a1_w + a2_w
	if tot_w > 0:
		text += "[color=yellow]── MATCH RECORD ──[/color]\n"
		text += "  %s: %d (%.0f%%)\n" % [a1.get("name", "Agent 1"), a1_w, 100.0 * a1_w / tot_w]
		text += "  %s: %d (%.0f%%)\n" % [a2.get("name", "Agent 2"), a2_w, 100.0 * a2_w / tot_w]

	_stats_label.text = text

	# Update heatmap data
	_hider_pos = data.get("hider_pos", Vector2i(-1, -1))
	_seeker_pos = data.get("seeker_pos", Vector2i(-1, -1))
	_q_value_grid = data.get("q_value_grid", [])
	_heatmap_panel.queue_redraw()


## Set the wall grid for heatmap background.
func set_wall_grid(grid: Array, w: int, h: int) -> void:
	_wall_grid = grid
	_grid_width = w
	_grid_height = h


func _build_ui() -> void:
	# Stats panel (top-left)
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.4)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_stats_panel.add_theme_stylebox_override("panel", style)
	_stats_panel.position = Vector2(10, 10)
	_stats_panel.size = Vector2(280, 0)

	_stats_label = RichTextLabel.new()
	_stats_label.name = "StatsLabel"
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.custom_minimum_size = Vector2(260, 100)
	_stats_label.add_theme_font_size_override("normal_font_size", 13)
	_stats_label.add_theme_font_size_override("bold_font_size", 15)
	_stats_panel.add_child(_stats_label)
	add_child(_stats_panel)

	# Heatmap panel (bottom-right)
	_heatmap_panel = Control.new()
	_heatmap_panel.name = "HeatmapPanel"
	_heatmap_panel.anchor_left = 1.0
	_heatmap_panel.anchor_top = 1.0
	_heatmap_panel.anchor_right = 1.0
	_heatmap_panel.anchor_bottom = 1.0
	_heatmap_panel.offset_left = -250
	_heatmap_panel.offset_top = -250
	_heatmap_panel.offset_right = -10
	_heatmap_panel.offset_bottom = -10
	_heatmap_panel.custom_minimum_size = Vector2(240, 240)
	_heatmap_panel.draw.connect(_draw_heatmap.bind(_heatmap_panel))
	add_child(_heatmap_panel)

	# Controls help (bottom-left)
	_controls_label = Label.new()
	_controls_label.name = "ControlsLabel"
	_controls_label.text = "WASD: Move | RMB: Look | Scroll: Speed | F: Seeker | G: Hider | H: Overview\nTAB: Toggle HUD | R (x5): Reset RL | 1-4: Speed"
	_controls_label.add_theme_font_size_override("font_size", 12)
	_controls_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_controls_label.anchor_left = 0.0
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_right = 0.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.offset_left = 12
	_controls_label.offset_top = -55
	_controls_label.offset_right = 650
	_controls_label.offset_bottom = -10
	# ── Round Timer Panel (TOP-CENTRE OF MAIN SCREEN) ──
	_timer_panel = PanelContainer.new()
	_timer_panel.name = "RoundTimerPanel"
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	t_style.border_width_left = 2
	t_style.border_width_right = 2
	t_style.border_width_top = 0
	t_style.border_width_bottom = 2
	t_style.border_color = Color(0.25, 0.55, 0.9, 0.85)
	t_style.corner_radius_bottom_left = 12
	t_style.corner_radius_bottom_right = 12
	t_style.content_margin_left = 20
	t_style.content_margin_right = 20
	t_style.content_margin_top = 6
	t_style.content_margin_bottom = 8
	_timer_panel.add_theme_stylebox_override("panel", t_style)

	_timer_panel.anchor_left = 0.5
	_timer_panel.anchor_right = 0.5
	_timer_panel.anchor_top = 0.0
	_timer_panel.anchor_bottom = 0.0
	_timer_panel.offset_left = -150
	_timer_panel.offset_right = 150
	_timer_panel.offset_top = 0
	_timer_panel.offset_bottom = 58
	_timer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_timer_label = RichTextLabel.new()
	_timer_label.name = "RoundTimerLabel"
	_timer_label.bbcode_enabled = true
	_timer_label.fit_content = true
	_timer_label.scroll_active = false
	_timer_label.custom_minimum_size = Vector2(240, 44)
	_timer_label.add_theme_font_size_override("normal_font_size", 13)
	_timer_label.add_theme_font_size_override("bold_font_size", 22)
	_timer_panel.add_child(_timer_label)
	add_child(_timer_panel)

	add_child(_controls_label)


## Announce winner on the top-centre timer and HUD.
func show_round_winner(winner: String, winner_name: String = "") -> void:
	_banner_timer = 5.0
	var col := "#44ff88" if winner == "Hider" else "#ff4444"
	var sub := "Hider survived 3m (+100 PTS) | Seeker gets LOSS" if winner == "Hider" else "Seeker caught Hider (+100 PTS) | Hider gets LOSS"
	var title_text: String = "🏆 %s [%s] WINS!" % [winner_name.to_upper(), winner.to_upper()] if winner_name != "" else "🏆 %s WINS!" % winner.to_upper()
	_banner_text = "[center][b][font_size=17][color=%s]%s[/color][/font_size][/b]\n[font_size=11][color=#ffffff]%s[/color][/font_size]\n[font_size=10][color=#88ccff]🔄 SWAPPING ROLES FOR NEXT MATCH...[/color][/font_size][/center]" % [col, title_text, sub]
	if _timer_label:
		_timer_label.text = _banner_text
	show_toast("🏆 %s Won! Swapping roles and randomizing map..." % (winner_name if winner_name != "" else winner))


## Display a temporary notification in the HUD controls bar.
func show_toast(msg: String) -> void:
	if _controls_label:
		_controls_label.text = msg
		await get_tree().create_timer(3.0).timeout
		if _controls_label:
			_controls_label.text = "WASD: Move | RMB: Look | Scroll: Speed | F: Seeker | G: Hider | H: Overview\nTAB: Toggle HUD | R (x5): Reset RL | 1-4: Speed"


func _draw_heatmap(panel: Control) -> void:
	if _wall_grid.is_empty() or _grid_width <= 0 or _grid_height <= 0:
		return

	var panel_size: Vector2 = Vector2(240, 240)
	var cell_w: float = panel_size.x / _grid_width
	var cell_h: float = panel_size.y / _grid_height

	# Background
	panel.draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.05, 0.05, 0.08, 0.8))

	# Draw grid cells
	for x in range(_grid_width):
		for y in range(_grid_height):
			var rect := Rect2(x * cell_w, y * cell_h, cell_w - 0.5, cell_h - 0.5)
			if x < _wall_grid.size() and y < _wall_grid[x].size() and _wall_grid[x][y] == 1:
				panel.draw_rect(rect, Color(0.3, 0.28, 0.35))
			else:
				# Q-value coloring
				var q_color := Color(0.12, 0.12, 0.15)
				if _q_value_grid.size() > x and _q_value_grid[x].size() > y:
					var qv: float = _q_value_grid[x][y]
					if qv > 0:
						q_color = Color(0.1, 0.2 + qv * 0.6, 0.1)  # Green for positive
					elif qv < 0:
						q_color = Color(0.2 + absf(qv) * 0.6, 0.1, 0.1)  # Red for negative
				panel.draw_rect(rect, q_color)

	# Draw agent positions
	if _hider_pos.x >= 0:
		var hr := Rect2(_hider_pos.x * cell_w, _hider_pos.y * cell_h, cell_w, cell_h)
		panel.draw_rect(hr, Color(0.3, 0.5, 1.0, 0.9))
	if _seeker_pos.x >= 0:
		var sr := Rect2(_seeker_pos.x * cell_w, _seeker_pos.y * cell_h, cell_w, cell_h)
		panel.draw_rect(sr, Color(1.0, 0.35, 0.3, 0.9))

	# Border
	panel.draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.4, 0.4, 0.5), false, 1.0)

	# Title
	# (draw_string is complex in Godot 4, using a simpler approach)


func _format_number(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	elif n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)
