extends Node2D

@onready var outer_ring := $CoreVisuals/OuterRing as Line2D
@onready var inner_ring := $CoreVisuals/InnerRing as Line2D
@onready var energy := $CoreVisuals/Energy as Polygon2D
@onready var core_glow := $CoreVisuals/CoreGlow as Polygon2D
@onready var void_horizon := $Background/VoidHorizon as Line2D
@onready var fog_band := $Background/FogNear as Polygon2D
@onready var warning_lights: Array[CanvasItem] = [
	$Background/SignalLights/WarningLeft,
	$Background/SignalLights/WarningMid,
	$Background/SignalLights/WarningRight,
]
@onready var floor_alert := $Gameplay/LowerRecoveryArea/FloorAlert as CanvasItem
@onready var hanging_lamp := $HangingObjects/IndustrialLampLeft as RigidBody2D
@onready var hanging_sign := $HangingObjects/IndustrialSignRight as RigidBody2D

var _elapsed := 0.0
var _charge := 0.0
var _chaos_level := 0
var _floor_panic := false

func _process(delta: float) -> void:
	_elapsed += delta
	outer_ring.rotation = _elapsed * (0.22 + _chaos_level * 0.035)
	inner_ring.rotation = -_elapsed * (0.38 + _chaos_level * 0.05)
	var pulse := 1.0 + sin(_elapsed * (2.1 + _chaos_level * 0.45)) * (0.025 + _charge * 0.035)
	energy.scale = Vector2.ONE * pulse
	core_glow.scale = Vector2.ONE * (1.0 + (pulse - 1.0) * 1.8)
	core_glow.modulate = Color(1.0, 0.72 + _charge * 0.18, 0.72 - _charge * 0.28, 0.72)
	void_horizon.modulate.a = 0.42 + sin(_elapsed * 2.7) * 0.1
	fog_band.position.x = sin(_elapsed * 0.11) * 28.0
	for index: int in warning_lights.size():
		warning_lights[index].modulate.a = 0.35 + 0.5 * maxf(sin(_elapsed * 3.0 - index * 0.8), 0.0)
	if _floor_panic:
		floor_alert.modulate.a = 0.35 + 0.45 * maxf(sin(_elapsed * 8.0), 0.0)

func _physics_process(_delta: float) -> void:
	# A subtle ventilation draft keeps both jointed fixtures readable as physics objects.
	hanging_lamp.apply_torque(sin(_elapsed * 0.9) * 18000.0)
	hanging_sign.apply_torque(-sin(_elapsed * 0.72 + 0.8) * 22000.0)

func set_reactor_state(charge: float, level: int) -> void:
	_charge = clampf(charge, 0.0, 1.0)
	_chaos_level = clampi(level, 0, 4)
	var cool_color := Color("58dcff")
	var hot_color := Color("ff5d70")
	energy.color = cool_color.lerp(hot_color, _charge)
	outer_ring.default_color = Color("74e5ff").lerp(Color("ff9a62"), _charge)

func set_floor_panic_state(enabled: bool) -> void:
	_floor_panic = enabled
	floor_alert.visible = enabled
	if not enabled:
		floor_alert.modulate.a = 0.0
