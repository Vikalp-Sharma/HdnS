## Factory for building distinct, high-detail sci-fi character bodies for AIAgents.
## Distinctly transforms agent anatomy per role:
## - HIDER: Sleek stealth infiltrator with glowing cyan visor, cloaking glider fins, chest core, and low-profile pauldrons.
## - SEEKER: Heavy combat apex hunter with menacing dual laser-red eyes, armored brow, radar tracking horns, heavy battlements, and dual dorsal pursuit thrusters.
class_name AgentBodyBuilder
extends RefCounted


static func build_body(parent: Node3D, role: int, is_showcase: bool = false) -> void:
	if parent == null:
		return

	# Remove existing body meshes while preserving any other children
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

	# 0 = HIDER, 1 = SEEKER
	if role == 0:
		_build_hider_body(parent, is_showcase)
	else:
		_build_seeker_body(parent, is_showcase)


# ══════════════════════════════════════════════════════════════
#  HIDER — STEALTH INFILTRATOR / CYBER GHOST
# ══════════════════════════════════════════════════════════════
static func _build_hider_body(root: Node3D, is_showcase: bool) -> void:
	var base_y: float = 1.0 if is_showcase else 0.95

	# 1. Main Core Torso — Sleek, streamlined navy capsule
	var torso_mi := MeshInstance3D.new()
	torso_mi.name = "Torso"
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.33
	torso_mesh.height = 1.35
	torso_mi.mesh = torso_mesh

	var torso_mat := StandardMaterial3D.new()
	torso_mat.albedo_color = Color(0.12, 0.28, 0.75)  # Stealth Cobalt Blue
	torso_mat.metallic = 0.45
	torso_mat.roughness = 0.22
	torso_mat.emission_enabled = true
	torso_mat.emission = Color(0.08, 0.35, 0.85)
	torso_mat.emission_energy_multiplier = 0.6
	torso_mi.material_override = torso_mat
	torso_mi.position = Vector3(0, base_y, 0)
	root.add_child(torso_mi)

	# 2. Horizontal Curved Stealth Visor (Cyberpunk HUD optics)
	var visor_mi := MeshInstance3D.new()
	visor_mi.name = "StealthVisor"
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.36, 0.11, 0.16)
	visor_mi.mesh = visor_mesh

	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.1, 0.92, 1.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.15, 0.95, 1.0)
	visor_mat.emission_energy_multiplier = 3.5
	visor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor_mi.material_override = visor_mat
	visor_mi.position = Vector3(0, 0.32, -0.30)
	torso_mi.add_child(visor_mi)

	# 3. Quantum Stealth Core — Glowing cyan reactor on chest
	var core_mi := MeshInstance3D.new()
	core_mi.name = "StealthCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.08
	core_mesh.bottom_radius = 0.08
	core_mesh.height = 0.04
	core_mi.mesh = core_mesh

	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.2, 1.0, 0.9)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.2, 1.0, 0.9)
	core_mat.emission_energy_multiplier = 3.0
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mi.material_override = core_mat
	core_mi.rotation = Vector3(deg_to_rad(90), 0, 0)
	core_mi.position = Vector3(0, 0.06, -0.33)
	torso_mi.add_child(core_mi)

	# 4. Aerodynamic Shoulder Pauldrons
	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.16, 0.18, 0.26)
	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.08, 0.16, 0.45)
	p_mat.metallic = 0.5
	p_mat.roughness = 0.3

	var left_p := MeshInstance3D.new()
	left_p.name = "LeftPauldron"
	left_p.mesh = p_mesh
	left_p.material_override = p_mat
	left_p.position = Vector3(-0.36, 0.18, 0.0)
	torso_mi.add_child(left_p)

	var right_p := MeshInstance3D.new()
	right_p.name = "RightPauldron"
	right_p.mesh = p_mesh
	right_p.material_override = p_mat
	right_p.position = Vector3(0.36, 0.18, 0.0)
	torso_mi.add_child(right_p)

	# 5. Cloaking Energy Glider Fins (Swept-back aerodynamic wings)
	var fin_mesh := BoxMesh.new()
	fin_mesh.size = Vector3(0.04, 0.42, 0.22)
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.08, 0.18, 0.55)
	fin_mat.emission_enabled = true
	fin_mat.emission = Color(0.1, 0.6, 1.0)
	fin_mat.emission_energy_multiplier = 0.8
	fin_mat.metallic = 0.6

	var left_fin := MeshInstance3D.new()
	left_fin.name = "LeftCloakingFin"
	left_fin.mesh = fin_mesh
	left_fin.material_override = fin_mat
	left_fin.position = Vector3(-0.22, 0.16, 0.26)
	left_fin.rotation = Vector3(deg_to_rad(-16), deg_to_rad(22), 0)
	torso_mi.add_child(left_fin)

	var right_fin := MeshInstance3D.new()
	right_fin.name = "RightCloakingFin"
	right_fin.mesh = fin_mesh
	right_fin.material_override = fin_mat
	right_fin.position = Vector3(0.22, 0.16, 0.26)
	right_fin.rotation = Vector3(deg_to_rad(-16), deg_to_rad(-22), 0)
	torso_mi.add_child(right_fin)

	# 6. Stealth Belt / Field Emitter Ring
	var belt_mi := MeshInstance3D.new()
	belt_mi.name = "StealthBelt"
	var belt_mesh := CylinderMesh.new()
	belt_mesh.top_radius = 0.36
	belt_mesh.bottom_radius = 0.36
	belt_mesh.height = 0.04
	belt_mi.mesh = belt_mesh
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color(0.05, 0.5, 0.7)
	belt_mat.emission_enabled = true
	belt_mat.emission = Color(0.1, 0.8, 0.9)
	belt_mat.emission_energy_multiplier = 1.0
	belt_mi.material_override = belt_mat
	belt_mi.position = Vector3(0, -0.22, 0)
	torso_mi.add_child(belt_mi)


# ══════════════════════════════════════════════════════════════
#  SEEKER — APEX HUNTER / COMBAT TRACKER
# ══════════════════════════════════════════════════════════════
static func _build_seeker_body(root: Node3D, is_showcase: bool) -> void:
	var base_y: float = 1.0 if is_showcase else 0.95

	# 1. Heavy Combat Chassis — Bulkier, armored crimson chassis
	var torso_mi := MeshInstance3D.new()
	torso_mi.name = "Torso"
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.39
	torso_mesh.height = 1.48
	torso_mi.mesh = torso_mesh

	var torso_mat := StandardMaterial3D.new()
	torso_mat.albedo_color = Color(0.85, 0.12, 0.12)  # Menacing Crimson Red
	torso_mat.metallic = 0.65
	torso_mat.roughness = 0.28
	torso_mat.emission_enabled = true
	torso_mat.emission = Color(0.7, 0.1, 0.08)
	torso_mat.emission_energy_multiplier = 0.7
	torso_mi.material_override = torso_mat
	torso_mi.position = Vector3(0, base_y, 0)
	root.add_child(torso_mi)

	# 2. Armored Brow Visor (Aggressive scowling battle plate)
	var brow_mi := MeshInstance3D.new()
	brow_mi.name = "ArmoredBrow"
	var brow_mesh := BoxMesh.new()
	brow_mesh.size = Vector3(0.40, 0.07, 0.18)
	brow_mi.mesh = brow_mesh
	var brow_mat := StandardMaterial3D.new()
	brow_mat.albedo_color = Color(0.12, 0.12, 0.14)  # Carbon Black
	brow_mat.metallic = 0.7
	brow_mat.roughness = 0.3
	brow_mi.material_override = brow_mat
	brow_mi.position = Vector3(0, 0.44, -0.26)
	brow_mi.rotation = Vector3(deg_to_rad(12), 0, 0)
	torso_mi.add_child(brow_mi)

	# 3. Dual Predator Optics — Piercing laser-red eyes
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.075
	eye_mesh.height = 0.15
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.05, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.05, 0.05)
	eye_mat.emission_energy_multiplier = 5.0
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var left_eye := MeshInstance3D.new()
	left_eye.name = "LeftPredatorOptic"
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.13, 0.36, -0.36)
	torso_mi.add_child(left_eye)

	var right_eye := MeshInstance3D.new()
	right_eye.name = "RightPredatorOptic"
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.13, 0.36, -0.36)
	torso_mi.add_child(right_eye)

	# 4. Long-Range Radar Tracker Horns (Dual antenna sensor spikes on head)
	var horn_mesh := CylinderMesh.new()
	horn_mesh.top_radius = 0.02
	horn_mesh.bottom_radius = 0.045
	horn_mesh.height = 0.36
	var horn_mat := StandardMaterial3D.new()
	horn_mat.albedo_color = Color(0.15, 0.15, 0.18)
	horn_mat.metallic = 0.8
	horn_mat.roughness = 0.25

	var left_horn := MeshInstance3D.new()
	left_horn.name = "LeftSensorHorn"
	left_horn.mesh = horn_mesh
	left_horn.material_override = horn_mat
	left_horn.position = Vector3(-0.16, 0.82, -0.04)
	left_horn.rotation = Vector3(deg_to_rad(10), 0, deg_to_rad(16))
	torso_mi.add_child(left_horn)

	var right_horn := MeshInstance3D.new()
	right_horn.name = "RightSensorHorn"
	right_horn.mesh = horn_mesh
	right_horn.material_override = horn_mat
	right_horn.position = Vector3(0.16, 0.82, -0.04)
	right_horn.rotation = Vector3(deg_to_rad(10), 0, deg_to_rad(-16))
	torso_mi.add_child(right_horn)

	# Central dorsal sensor mast & beacon light
	var mast_mi := MeshInstance3D.new()
	mast_mi.name = "RadarFin"
	var mast_mesh := BoxMesh.new()
	mast_mesh.size = Vector3(0.05, 0.20, 0.22)
	mast_mi.mesh = mast_mesh
	mast_mi.material_override = horn_mat
	mast_mi.position = Vector3(0, 0.80, 0.08)
	torso_mi.add_child(mast_mi)

	var beacon_mi := MeshInstance3D.new()
	beacon_mi.name = "TrackerBeacon"
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.05
	beacon_mesh.height = 0.10
	beacon_mi.mesh = beacon_mesh
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.25, 0.1)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.25, 0.1)
	beacon_mat.emission_energy_multiplier = 4.0
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mi.material_override = beacon_mat
	beacon_mi.position = Vector3(0, 0.12, 0.08)
	mast_mi.add_child(beacon_mi)

	# 5. Heavy Armored Combat Pauldrons (Shoulders)
	var bp_mesh := BoxMesh.new()
	bp_mesh.size = Vector3(0.24, 0.26, 0.32)
	var bp_mat := StandardMaterial3D.new()
	bp_mat.albedo_color = Color(0.25, 0.06, 0.06)
	bp_mat.metallic = 0.7
	bp_mat.roughness = 0.35

	var left_bp := MeshInstance3D.new()
	left_bp.name = "LeftCombatPauldron"
	left_bp.mesh = bp_mesh
	left_bp.material_override = bp_mat
	left_bp.position = Vector3(-0.46, 0.24, 0.0)
	torso_mi.add_child(left_bp)

	var right_bp := MeshInstance3D.new()
	right_bp.name = "RightCombatPauldron"
	right_bp.mesh = bp_mesh
	right_bp.material_override = bp_mat
	right_bp.position = Vector3(0.46, 0.24, 0.0)
	torso_mi.add_child(right_bp)

	# 6. Dorsal Pursuit Thrusters (Heavy twin rocket engines on back)
	var thruster_mesh := CylinderMesh.new()
	thruster_mesh.top_radius = 0.10
	thruster_mesh.bottom_radius = 0.10
	thruster_mesh.height = 0.46
	var thruster_mat := StandardMaterial3D.new()
	thruster_mat.albedo_color = Color(0.18, 0.18, 0.20)
	thruster_mat.metallic = 0.75
	thruster_mat.roughness = 0.25

	var nozzle_mesh := CylinderMesh.new()
	nozzle_mesh.top_radius = 0.08
	nozzle_mesh.bottom_radius = 0.08
	nozzle_mesh.height = 0.06
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(1.0, 0.4, 0.0)
	nozzle_mat.emission_enabled = true
	nozzle_mat.emission = Color(1.0, 0.45, 0.05)
	nozzle_mat.emission_energy_multiplier = 4.0
	nozzle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Left thruster
	var left_thruster := MeshInstance3D.new()
	left_thruster.name = "LeftPursuitThruster"
	left_thruster.mesh = thruster_mesh
	left_thruster.material_override = thruster_mat
	left_thruster.position = Vector3(-0.21, 0.18, 0.34)
	left_thruster.rotation = Vector3(deg_to_rad(10), 0, 0)
	torso_mi.add_child(left_thruster)

	var left_nozzle := MeshInstance3D.new()
	left_nozzle.mesh = nozzle_mesh
	left_nozzle.material_override = nozzle_mat
	left_nozzle.position = Vector3(0, -0.24, 0)
	left_thruster.add_child(left_nozzle)

	# Right thruster
	var right_thruster := MeshInstance3D.new()
	right_thruster.name = "RightPursuitThruster"
	right_thruster.mesh = thruster_mesh
	right_thruster.material_override = thruster_mat
	right_thruster.position = Vector3(0.21, 0.18, 0.34)
	right_thruster.rotation = Vector3(deg_to_rad(10), 0, 0)
	torso_mi.add_child(right_thruster)

	var right_nozzle := MeshInstance3D.new()
	right_nozzle.mesh = nozzle_mesh
	right_nozzle.material_override = nozzle_mat
	right_nozzle.position = Vector3(0, -0.24, 0)
	right_thruster.add_child(right_nozzle)

	# 7. Reinforced Front Chest Battleplate
	var chest_mi := MeshInstance3D.new()
	chest_mi.name = "ChestBattleplate"
	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.32, 0.32, 0.10)
	chest_mi.mesh = chest_mesh
	var chest_mat := StandardMaterial3D.new()
	chest_mat.albedo_color = Color(0.15, 0.15, 0.18)
	chest_mat.metallic = 0.8
	chest_mat.roughness = 0.3
	chest_mat.emission_enabled = true
	chest_mat.emission = Color(0.8, 0.15, 0.1)
	chest_mat.emission_energy_multiplier = 0.8
	chest_mi.material_override = chest_mat
	chest_mi.position = Vector3(0, 0.05, -0.34)
	torso_mi.add_child(chest_mi)
