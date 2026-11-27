extends Node3D
# مزرعتي 3D — لعبة مزارع جماعية: خريطة واحدة وسيرفر واحد ومزرعة لكل لاعب.

# ضع رابط Firebase Realtime Database هنا، مثال:
# https://my-farm-default-rtdb.firebaseio.com
# إذا تركته كما هو تعمل اللعبة فردية بدون سيرفر.
const DB_URL := "PUT_YOUR_FIREBASE_URL_HERE"

const CELL := 5.0
const COLS := 8
const ROWS := 6
const NCELLS := 48
const TUFT_COLS := 6
const TUFT_ROWS := 4
const TUFTS := 24
const FW := 40.0
const FH := 30.0
const SLOTS_X := 5
const NSLOTS := 20
const LOT_DX := 70.0
const LOT_DZ := 60.0
const MAX_SPEED := 9.0
const ACCEL := 10.0
const TURN_RATE := 1.7
const DAY_SECONDS := 720.0
const YIELD_PER_CELL := 5
const MARKET_POS := Vector3(0.0, 0.0, 0.0)
const MARKET_RANGE := 14.0
const SOIL_RAW := Color(0.26, 0.34, 0.12, 0.0)
const SOIL_PLOWED := Color(0.2, 0.12, 0.065, 1.0)
const CROPS := [
	{"n": "قمح", "grow": 40.0, "price": 12, "h": 0.95, "c": Color(0.78, 0.58, 0.18)},
	{"n": "شعير", "grow": 30.0, "price": 10, "h": 0.85, "c": Color(0.66, 0.62, 0.24)},
	{"n": "ذرة", "grow": 70.0, "price": 18, "h": 2.1, "c": Color(0.62, 0.52, 0.12)},
	{"n": "كانولا", "grow": 55.0, "price": 15, "h": 1.2, "c": Color(0.9, 0.72, 0.05)},
]
const TOOL_NAMES := ["محراث", "بذّار", "حصّادة"]
const QUALITY_NAMES := ["منخفضة", "متوسطة", "عالية"]

const GROUND_SHADER := """
shader_type spatial;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float height(vec2 p) {
	float edge = max(smoothstep(215.0, 330.0, abs(p.x)), smoothstep(165.0, 260.0, abs(p.y)));
	float n = noise(p * 0.011) * 0.65 + noise(p * 0.035) * 0.35;
	return edge * (5.0 + 55.0 * n);
}
void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float h = height(w.xz);
	VERTEX.y += h;
	float e = 5.0;
	NORMAL = normalize(vec3(height(w.xz - vec2(e, 0.0)) - height(w.xz + vec2(e, 0.0)), 2.0 * e, height(w.xz - vec2(0.0, e)) - height(w.xz + vec2(0.0, e))));
	wpos = vec3(w.x, h, w.z);
}
void fragment() {
	float n1 = noise(wpos.xz * 0.04);
	float n2 = noise(wpos.xz * 0.3);
	float grain = hash(floor(wpos.xz * 3.0));
	vec3 g1 = vec3(0.1, 0.27, 0.08);
	vec3 g2 = vec3(0.2, 0.38, 0.1);
	vec3 dry = vec3(0.36, 0.32, 0.14);
	vec3 col = mix(g1, g2, n1);
	col = mix(col, dry, smoothstep(0.6, 0.9, noise(wpos.xz * 0.02 + 7.0)) * 0.5);
	col *= 0.85 + 0.3 * n2;
	col *= 0.93 + 0.14 * grain;
	float dx = abs(mod(wpos.x, 70.0) - 35.0);
	float mz = mod(wpos.z, 60.0);
	float dz = min(mz, 60.0 - mz);
	float road = max(1.0 - smoothstep(3.0, 4.5, dx), 1.0 - smoothstep(3.0, 4.5, dz));
	road *= 1.0 - smoothstep(0.3, 1.5, wpos.y);
	vec3 dirt = vec3(0.32, 0.25, 0.16) * (0.88 + 0.24 * grain);
	col = mix(col, dirt, road);
	col = mix(col, vec3(0.22, 0.2, 0.17) * (0.7 + 0.6 * n2), smoothstep(16.0, 42.0, wpos.y));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

const SOIL_SHADER := """
shader_type spatial;
varying vec4 vcol;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { vcol = COLOR; }
void fragment() {
	float grain = hash(floor(UV * 40.0));
	float furrow = 0.5 + 0.5 * sin(UV.y * 6.2831 * 6.0);
	float shade = mix(1.0, 0.55 + 0.45 * furrow, vcol.a);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	shade *= 0.72 + 0.28 * smoothstep(0.0, 0.12, edge);
	ALBEDO = vcol.rgb * shade * (0.86 + 0.28 * grain);
	ROUGHNESS = 1.0;
}
"""

const CROP_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float now_rel = 0.0;
const float HMAX[4] = float[4](0.95, 0.85, 2.1, 1.2);
const float THICK[4] = float[4](1.0, 1.0, 2.2, 1.3);
const vec3 RIPE[4] = vec3[4](vec3(0.78, 0.58, 0.18), vec3(0.66, 0.62, 0.24), vec3(0.62, 0.52, 0.12), vec3(0.9, 0.72, 0.05));
varying vec3 vcolor;
void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int k = clamp(int(cd.z + 0.5), 0, 3);
	float g = clamp((now_rel - cd.x) / max(cd.y, 1.0), 0.0, 1.0);
	float on = step(0.5, cd.w);
	vec3 v = VERTEX;
	v.xz *= mix(0.6, 1.0, g) * THICK[k] * on;
	v.y *= mix(0.12, HMAX[k], g) * on;
	v.x += sin(now_rel * 1.7 + MODEL_MATRIX[3].x * 0.6 + MODEL_MATRIX[3].z * 0.4) * 0.06 * v.y;
	VERTEX = v;
	float ripe = clamp(g * 1.3 - 0.15, 0.0, 1.0);
	vec3 base = mix(vec3(0.08, 0.28, 0.06), RIPE[k], ripe);
	vec3 stem = base * mix(0.55, 1.0, COLOR.r);
	float flower = (k == 3) ? step(0.5, g) : step(0.9, g);
	vec3 headc = (k == 3) ? vec3(1.0, 0.82, 0.05) : RIPE[k] * 1.1;
	vcolor = mix(stem, headc, COLOR.a * flower);
}
void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = vcolor;
	ROUGHNESS = 0.9;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec3 vc;
void vertex() {
	VERTEX.x += sin(TIME * 1.8 + MODEL_MATRIX[3].x * 0.5 + MODEL_MATRIX[3].z * 0.3) * 0.14 * VERTEX.y;
	vc = COLOR.rgb;
}
void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = vc;
	ROUGHNESS = 1.0;
}
"""

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wp.xz * 0.0045 + vec2(TIME * 0.006, 0.0);
	float n = fbm(uv);
	float a = smoothstep(0.52, 0.8, n);
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	a *= 1.0 - smoothstep(700.0, 1500.0, d);
	ALBEDO = tint * (0.8 + 0.3 * (1.0 - n));
	ALPHA = a * 0.9;
}
"""


# ---------------------------------------------------------------- بيانات المزرعة
class FarmData:
	const N := 48
	var st := PackedInt32Array()
	var cr := PackedInt32Array()
	var pt := PackedFloat64Array()
	var ripe_shown := PackedByteArray()
	var inv := [0, 0, 0, 0]
	var coins := 0

	func _init() -> void:
		st.resize(N)
		cr.resize(N)
		pt.resize(N)
		ripe_shown.resize(N)

	func to_dict() -> Dictionary:
		var parts := PackedStringArray()
		for i in N:
			parts.append("%d-%d-%d" % [st[i], cr[i], int(pt[i])])
		return {
			"t": ",".join(parts),
			"c": coins,
			"i": "%d,%d,%d,%d" % [inv[0], inv[1], inv[2], inv[3]],
		}

	func load_dict(d: Variant) -> void:
		if not (d is Dictionary):
			return
		var parts := str(d.get("t", "")).split(",")
		for i in range(mini(parts.size(), N)):
			var q := parts[i].split("-")
			if q.size() == 3:
				st[i] = clampi(int(q[0]), 0, 2)
				cr[i] = clampi(int(q[1]), 0, 3)
				pt[i] = float(q[2])
		ripe_shown.fill(0)
		coins = int(d.get("c", 0))
		var iv := str(d.get("i", "")).split(",")
		for k in range(mini(iv.size(), 4)):
			inv[k] = int(iv[k])


# ---------------------------------------------------------------- الجرار
class Tractor:
	extends Node3D
	const PIV := 0.9
	var body: Node3D
	var _wheels: Array = []
	var _steer_pivots: Array = []
	var _impl: Array = []
	var _reel: Node3D
	var _label: Label3D
	var _dust: Array = []
	var _pitch := 0.0
	var _roll := 0.0
	var _last_speed := 0.0
	var _vib := 0.0

	func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, rough: float = 0.7, metal: float = 0.0, emit: bool = false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _mat(color, rough, metal, emit)
		mi.position = pos
		parent.add_child(mi)
		return mi

	func _cyl(parent: Node3D, r: float, h: float, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, metal: float = 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 20
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _mat(color, 0.6, metal, false)
		mi.position = pos
		mi.rotation_degrees = rot
		parent.add_child(mi)
		return mi

	func _mat(color: Color, rough: float, metal: float, emit: bool) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emit:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 1.6
		return m

	func _capsule(pos: Vector3, r: float, h: float, color: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = h
		cm.radial_segments = 16
		cm.rings = 4
		mi.mesh = cm
		mi.material_override = _mat(color, 0.4, 0.3, false)
		mi.position = pos - Vector3(0, PIV, 0)
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.scale = Vector3(1.15, 1.0, 0.8)
		body.add_child(mi)
		return mi

	func _bb(size: Vector3, color: Color, pos: Vector3, rough: float = 0.7, metal: float = 0.0, emit: bool = false) -> MeshInstance3D:
		return _box(body, size, color, pos - Vector3(0, PIV, 0), rough, metal, emit)

	func _wheel(pos: Vector3, radius: float, width: float, rim_col: Color, steer: bool) -> void:
		var holder := Node3D.new()
		holder.position = pos
		add_child(holder)
		if steer:
			_steer_pivots.append(holder)
		var pivot := Node3D.new()
		holder.add_child(pivot)
		_cyl(pivot, radius, width, Color(0.07, 0.07, 0.07), Vector3.ZERO, Vector3(0, 0, 90))
		_cyl(pivot, radius * 0.58, width + 0.05, rim_col, Vector3.ZERO, Vector3(0, 0, 90))
		for k in 10:
			var a := TAU * float(k) / 10.0
			var lug := _box(pivot, Vector3(width + 0.06, 0.11, 0.22), Color(0.05, 0.05, 0.05), Vector3(0, cos(a) * radius, sin(a) * radius))
			lug.rotation.x = a
		_wheels.append([pivot, radius])

	func _impl_node(pos: Vector3) -> Node3D:
		var n := Node3D.new()
		n.position = pos - Vector3(0, PIV, 0)
		n.visible = false
		body.add_child(n)
		_impl.append(n)
		return n

	func _make_dust(pos: Vector3, mat: Material) -> void:
		var p := CPUParticles3D.new()
		p.position = pos
		p.amount = 20
		p.lifetime = 1.1
		p.local_coords = false
		p.emitting = false
		p.direction = Vector3(0, 1, 0.6)
		p.spread = 35.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.8
		p.gravity = Vector3(0, 0.25, 0)
		p.scale_amount_min = 0.9
		p.scale_amount_max = 1.7
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(0.72, 0.62, 0.48, 0.5))
		grad.set_color(1, Color(0.72, 0.62, 0.48, 0.0))
		p.color_ramp = grad
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		qm.material = mat
		p.mesh = qm
		add_child(p)
		_dust.append(p)

	func build(color: Color, label_text: String, font: Font, dust_mat: Material) -> void:
		body = Node3D.new()
		body.position = Vector3(0, PIV, 0)
		add_child(body)
		var steel := Color(0.16, 0.16, 0.18)
		_bb(Vector3(1.5, 0.55, 3.7), steel, Vector3(0, 0.95, 0.1), 0.5, 0.5)
		_capsule(Vector3(0, 1.62, -1.15), 0.62, 2.0, color)
		_bb(Vector3(1.25, 0.55, 0.08), Color(0.08, 0.08, 0.08), Vector3(0, 1.55, -2.17))
		for sx in [-0.52, 0.52]:
			_bb(Vector3(0.3, 0.2, 0.07), Color(1.0, 0.95, 0.8), Vector3(sx, 1.78, -2.19), 0.3, 0.0, true)
		_cyl(body, 0.07, 1.1, Color(0.12, 0.12, 0.13), Vector3(-0.5, 2.55 - PIV, -1.75), Vector3.ZERO, 0.6)
		_bb(Vector3(1.7, 0.14, 1.7), steel, Vector3(0, 1.3, 0.75))
		for cx in [-0.8, 0.8]:
			for cz in [-0.05, 1.55]:
				_bb(Vector3(0.1, 1.6, 0.1), color.darkened(0.1), Vector3(cx, 2.15, cz))
		_bb(Vector3(1.95, 0.12, 1.95), color.lightened(0.1), Vector3(0, 3.0, 0.75))
		_bb(Vector3(1.62, 1.4, 1.52), Color(0.55, 0.75, 0.9, 0.32), Vector3(0, 2.15, 0.75), 0.1)
		_bb(Vector3(0.55, 0.5, 0.45), Color(0.1, 0.1, 0.1), Vector3(0, 1.7, 1.1))
		_bb(Vector3(0.55, 0.7, 0.12), Color(0.1, 0.1, 0.1), Vector3(0, 2.1, 1.35))
		_cyl(body, 0.2, 0.05, Color(0.05, 0.05, 0.05), Vector3(0, 2.0 - PIV, 0.2), Vector3(70, 0, 0))
		_cyl(body, 0.08, 0.14, Color(1.0, 0.55, 0.05), Vector3(0.7, 3.12 - PIV, 1.4), Vector3.ZERO, 0.0)
		for sx in [-1.2, 1.2]:
			_bb(Vector3(0.75, 0.1, 1.95), color.darkened(0.05), Vector3(sx, 1.95, 1.0))
		_bb(Vector3(0.9, 0.3, 0.4), steel, Vector3(0, 0.7, 2.2))
		var rim := Color(0.95, 0.75, 0.1)
		for sx in [-1.15, 1.15]:
			_wheel(Vector3(sx, 0.9, 1.0), 0.9, 0.6, rim, false)
		for sx in [-1.0, 1.0]:
			_wheel(Vector3(sx, 0.55, -1.4), 0.55, 0.4, rim, true)
		# محراث (خلف)
		var plow := _impl_node(Vector3(0, 0.7, 2.9))
		_box(plow, Vector3(2.4, 0.15, 0.25), Color(0.2, 0.2, 0.22), Vector3(0, 0.3, 0))
		for px in [-0.8, 0.0, 0.8]:
			_box(plow, Vector3(0.1, 0.55, 0.1), Color(0.25, 0.25, 0.28), Vector3(px, 0.0, 0.0))
			var share := _box(plow, Vector3(0.5, 0.08, 0.95), Color(0.65, 0.65, 0.7), Vector3(px, -0.3, 0.35), 0.4, 0.8)
			share.rotation_degrees = Vector3(-18, 0, 0)
		# بذّار (خلف)
		var seeder := _impl_node(Vector3(0, 0.95, 2.9))
		_box(seeder, Vector3(2.4, 0.7, 0.85), Color(0.15, 0.35, 0.8), Vector3(0, 0.35, 0))
		_box(seeder, Vector3(2.5, 0.08, 0.95), Color(0.1, 0.1, 0.12), Vector3(0, 0.74, 0))
		for sx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			_cyl(seeder, 0.04, 0.8, Color(0.3, 0.3, 0.32), Vector3(sx, -0.25, 0.1))
		# حصّادة (أمام)
		var header := _impl_node(Vector3(0, 0.6, -3.25))
		_box(header, Vector3(3.6, 0.5, 1.1), Color(0.75, 0.12, 0.1), Vector3(0, 0, 0))
		_box(header, Vector3(3.6, 0.08, 0.25), Color(0.6, 0.6, 0.65), Vector3(0, -0.25, -0.6), 0.4, 0.8)
		for sx in [-1.78, 1.78]:
			_box(header, Vector3(0.08, 0.95, 1.3), Color(0.7, 0.1, 0.08), Vector3(sx, 0.2, -0.05))
		_reel = Node3D.new()
		_reel.position = Vector3(0, 0.6, -0.45)
		header.add_child(_reel)
		_cyl(_reel, 0.28, 3.4, Color(0.9, 0.75, 0.1), Vector3.ZERO, Vector3(0, 0, 90))
		for k in 4:
			var a := TAU * float(k) / 4.0
			var bat := _box(_reel, Vector3(3.4, 0.07, 0.3), Color(0.9, 0.75, 0.1), Vector3(0, cos(a) * 0.55, sin(a) * 0.55))
			bat.rotation.x = a
		_make_dust(Vector3(-1.15, 0.15, 1.7), dust_mat)
		_make_dust(Vector3(1.15, 0.15, 1.7), dust_mat)
		_label = Label3D.new()
		_label.text = label_text
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 56
		_label.pixel_size = 0.01
		_label.outline_size = 14
		_label.no_depth_test = true
		_label.position = Vector3(0, 4.7, 0)
		if font != null:
			_label.font = font
		add_child(_label)

	func set_label(t: String) -> void:
		if _label != null and _label.text != t:
			_label.text = t

	func set_tool(i: int) -> void:
		for k in _impl.size():
			(_impl[k] as Node3D).visible = (k == i)

	func spin(dist: float) -> void:
		for w in _wheels:
			(w[0] as Node3D).rotation.x -= dist / float(w[1])
		if _reel != null and _reel.get_parent().visible:
			_reel.rotation.x -= dist * 1.4 + 0.02

	func update_motion(speed: float, steer: float, delta: float, dust_on: bool) -> void:
		var acc := (speed - _last_speed) / maxf(delta, 0.001)
		_last_speed = speed
		var k := minf(delta * 6.0, 1.0)
		_pitch = lerpf(_pitch, clampf(acc * 0.012, -0.06, 0.06), k)
		_roll = lerpf(_roll, clampf(steer * speed * 0.007, -0.05, 0.05), k)
		_vib += delta * (30.0 + absf(speed) * 3.0)
		var amp := 0.006 + absf(speed) * 0.0012
		body.rotation = Vector3(_pitch + sin(_vib * 1.3) * amp * 0.5, 0.0, _roll + sin(_vib) * amp * 0.5)
		body.position = Vector3(0, PIV + sin(_vib * 1.7) * amp, 0)
		for sp in _steer_pivots:
			(sp as Node3D).rotation.y = lerp_angle((sp as Node3D).rotation.y, -steer * 0.5, k)
		var dusty := dust_on and absf(speed) > 2.0
		for p in _dust:
			(p as CPUParticles3D).emitting = dusty


# ---------------------------------------------------------------- واجهة اللمس
class Hud:
	extends Control
	signal tool_pressed(index: int)
	signal crop_pressed
	signal sell_pressed
	signal sound_pressed
	signal quality_pressed

	const STICK_R := 110.0

	var info: Dictionary = {}
	var stick := Vector2.ZERO
	var tool_names: Array = []
	var quality_names: Array = []
	var font: Font
	var _stick_touch := -1
	var _stick_center := Vector2.ZERO
	var _buttons: Array = []
	var _sb := StyleBoxFlat.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(_layout)
		_sb.set_corner_radius_all(16)
		_layout()

	func _layout() -> void:
		var s := size
		if _stick_touch == -1:
			_stick_center = Vector2(190.0, s.y - 190.0)
		_buttons.clear()
		for k in 3:
			_buttons.append({"id": k, "rect": Rect2(s.x - 150.0 * (3 - k) - 10.0, s.y - 150.0, 135.0, 135.0)})
		_buttons.append({"id": 10, "rect": Rect2(s.x - 290.0, 80.0, 270.0, 80.0)})
		_buttons.append({"id": 11, "rect": Rect2(s.x - 340.0, s.y - 290.0, 320.0, 110.0)})
		_buttons.append({"id": 12, "rect": Rect2(10.0, 132.0, 160.0, 54.0)})
		_buttons.append({"id": 13, "rect": Rect2(180.0, 132.0, 160.0, 54.0)})

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var t := event as InputEventScreenTouch
			if t.pressed:
				_press(t.index, t.position)
			else:
				_release(t.index)
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			if d.index == _stick_touch:
				stick = ((d.position - _stick_center) / STICK_R).limit_length(1.0)

	func _press(idx: int, pos: Vector2) -> void:
		for b in _buttons:
			var id: int = b["id"]
			if id == 11 and not info.get("near_market", false):
				continue
			if (b["rect"] as Rect2).has_point(pos):
				if id < 3:
					tool_pressed.emit(id)
				elif id == 10:
					crop_pressed.emit()
				elif id == 11:
					sell_pressed.emit()
				elif id == 12:
					sound_pressed.emit()
				else:
					quality_pressed.emit()
				return
		if _stick_touch == -1 and pos.x < size.x * 0.5:
			_stick_touch = idx
			_stick_center = pos
			stick = Vector2.ZERO

	func _release(idx: int) -> void:
		if idx == _stick_touch:
			_stick_touch = -1
			stick = Vector2.ZERO
			_layout()

	func _panel(r: Rect2, c: Color) -> void:
		_sb.bg_color = c
		draw_style_box(_sb, r)

	func _t(f: Font, text: String, pos: Vector2, fsize: int, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
		draw_string(f, pos, text, align, width, fsize, Color.WHITE)

	func _draw() -> void:
		var s := size
		var f: Font = font if font != null else ThemeDB.fallback_font
		draw_circle(_stick_center, STICK_R, Color(1, 1, 1, 0.10))
		draw_arc(_stick_center, STICK_R, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_stick_center + stick * STICK_R, 44.0, Color(1, 1, 1, 0.35))

		_panel(Rect2(10, 10, 330, 58), Color(0, 0, 0, 0.5))
		_t(f, "العملات: %d" % int(info.get("coins", 0)), Vector2(24, 48), 28)
		_panel(Rect2(10, 76, 330, 46), Color(0, 0, 0, 0.4))
		_t(f, str(info.get("inv", "")), Vector2(24, 107), 21)
		_panel(Rect2(s.x * 0.5 - 70.0, 10, 140, 50), Color(0, 0, 0, 0.5))
		_t(f, str(info.get("time", "")), Vector2(s.x * 0.5 - 70.0, 46), 28, HORIZONTAL_ALIGNMENT_CENTER, 140.0)
		_panel(Rect2(s.x - 360.0, 10, 350, 58), Color(0, 0, 0, 0.5))
		_t(f, str(info.get("status", "")), Vector2(s.x - 360.0, 47), 24, HORIZONTAL_ALIGNMENT_CENTER, 350.0)

		var msg := str(info.get("msg", ""))
		if msg != "":
			_panel(Rect2(s.x * 0.5 - 260.0, 76, 520, 52), Color(0.1, 0.1, 0.1, 0.8))
			_t(f, msg, Vector2(s.x * 0.5 - 260.0, 111), 24, HORIZONTAL_ALIGNMENT_CENTER, 520.0)

		for b in _buttons:
			var id: int = b["id"]
			var r: Rect2 = b["rect"]
			var label := ""
			var col := Color(0, 0, 0, 0.55)
			var fs := 26
			if id < 3:
				label = str(tool_names[id])
				if int(info.get("tool", -1)) == id:
					col = Color(0.95, 0.7, 0.1, 0.9)
			elif id == 10:
				label = "المحصول: " + str(info.get("crop", ""))
				col = Color(0.1, 0.35, 0.15, 0.85)
			elif id == 11:
				if not info.get("near_market", false):
					continue
				label = "بيع المحاصيل"
				col = Color(0.15, 0.5, 0.2, 0.9)
			elif id == 12:
				label = "الصوت: " + ("تشغيل" if info.get("sound", true) else "إيقاف")
				fs = 20
			else:
				label = "الجودة: " + str(quality_names[int(info.get("quality", 1))])
				fs = 20
			_panel(r, col)
			_t(f, label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.35), fs, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ---------------------------------------------------------------- الحالة
var net_on := false
var base_url := ""
var my_id := ""
var my_name := ""
var my_slot := 0
var my_farm := FarmData.new()
var farms := {}
var farm_sigs := {}
var others := {}
var names := {}
var slot_owner: Array = []
var me: Tractor
var me_pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var steer_in := 0.0
var cam: Camera3D
var cam_yaw := 0.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var soil_mm: MultiMesh
var crop_mms: Array = []
var crop_nodes: Array = []
var crop_mat: ShaderMaterial
var clouds: MeshInstance3D
var clouds_mat: ShaderMaterial
var time_base := 0.0
var hud: Hud
var ui_font: Font
var dust_mat: StandardMaterial3D
var scenery := Node3D.new()
var grass_root := Node3D.new()
var tool_idx := -1
var crop_idx := 0
var quality := 1
var sound_on := true
var dust_on := true
var ready_to_play := false
var connected := false
var dirty := false
var msg := ""
var msg_until := 0.0
var time_text := "06:00"
var force_tod := -1.0
var slot_labels: Array = []
var slot_mats: Array = []
var _save_cd := 0.0
var _push_cd := 0.0
var _poll_cd := 0.0
var _farm_poll_cd := 0.0
var _day_cd := 0.0
var _pushing := false
var _polling := false
var _farm_polling := false
var _pushing_farm := false
var _audio: AudioStreamPlayer
var _audio_pb: AudioStreamGeneratorPlayback
var _eng_phase := 0.0


func _ready() -> void:
	randomize()
	time_base = Time.get_unix_time_from_system()
	base_url = DB_URL.strip_edges().rstrip("/")
	net_on = base_url.begins_with("https://")
	slot_owner.resize(NSLOTS)
	slot_owner.fill("")
	if ResourceLoader.exists("res://Tajawal-Bold.ttf"):
		ui_font = load("res://Tajawal-Bold.ttf") as Font
	_load_identity()
	_make_dust_material()
	_build_environment()
	_build_world()
	_build_scenery()
	_build_hud()
	_setup_audio()
	_apply_quality()
	await _join()
	_spawn_me()
	ready_to_play = true
	for s in NSLOTS:
		_update_slot_visual(s)
	_refresh_all()


# ---------------------------------------------------------------- بناء العالم
func slot_center(slot: int) -> Vector3:
	var col := slot % SLOTS_X
	var row := floori(float(slot) / SLOTS_X)
	return Vector3((col - 2) * LOT_DX, 0.0, (row - 1.5) * LOT_DZ)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _add_box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_label(text: String, pos: Vector3, fsize: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = fsize
	l.pixel_size = 0.012
	l.outline_size = 16
	l.no_depth_test = true
	l.position = pos
	if ui_font != null:
		l.font = ui_font
	add_child(l)
	return l


func _make_dust_material() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	dust_mat = StandardMaterial3D.new()
	dust_mat.albedo_texture = tex
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.vertex_color_use_as_albedo = true
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.billboard_keep_scale = true
	dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_environment() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	env.fog_enabled = true
	env.fog_density = 0.0022
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var cs := Shader.new()
	cs.code = CLOUD_SHADER
	clouds_mat = ShaderMaterial.new()
	clouds_mat.shader = cs
	clouds = MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(3200, 3200)
	clouds.mesh = cp
	clouds.material_override = clouds_mat
	clouds.position = Vector3(0, 260, 0)
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.far = 700.0
	add_child(cam)


func _make_multimesh(mesh: Mesh, count: int, shadows: bool, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = AABB(Vector3(-260, -5, -200), Vector3(520, 30, 400))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1200)
	pm.subdivide_width = 140
	pm.subdivide_depth = 120
	ground.mesh = pm
	var gs := Shader.new()
	gs.code = GROUND_SHADER
	var gm := ShaderMaterial.new()
	gm.shader = gs
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(4.6, 0.2, 4.6)
	var ss := Shader.new()
	ss.code = SOIL_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = ss
	soil_mm = _make_multimesh(soil_mesh, NSLOTS * NCELLS, false, sm)
	var cshader := Shader.new()
	cshader.code = CROP_SHADER
	crop_mat = ShaderMaterial.new()
	crop_mat.shader = cshader
	var plant := _plant_mesh()

	var fence_col := Color(0.5, 0.35, 0.2)
	for s in NSLOTS:
		var c := slot_center(s)
		var mat := _mat(Color(1, 1, 1, 0.55))
		slot_mats.append(mat)
		var holder := Node3D.new()
		holder.position = c
		add_child(holder)
		_add_box(holder, Vector3(FW + 3.0, 0.15, 0.15), mat, Vector3(0, 0.85, -FH * 0.5 - 1.5))
		_add_box(holder, Vector3(FW + 3.0, 0.15, 0.15), mat, Vector3(0, 0.85, FH * 0.5 + 1.5))
		_add_box(holder, Vector3(0.15, 0.15, FH + 3.0), mat, Vector3(-FW * 0.5 - 1.5, 0.85, 0))
		_add_box(holder, Vector3(0.15, 0.15, FH + 3.0), mat, Vector3(FW * 0.5 + 1.5, 0.85, 0))
		var post_mat := _mat(fence_col)
		for k in 9:
			var px := -FW * 0.5 - 1.5 + float(k) * (FW + 3.0) / 8.0
			_add_box(holder, Vector3(0.22, 1.1, 0.22), post_mat, Vector3(px, 0.55, -FH * 0.5 - 1.5))
			_add_box(holder, Vector3(0.22, 1.1, 0.22), post_mat, Vector3(px, 0.55, FH * 0.5 + 1.5))
		for k in range(1, 7):
			var pz := -FH * 0.5 - 1.5 + float(k) * (FH + 3.0) / 7.0
			_add_box(holder, Vector3(0.22, 1.1, 0.22), post_mat, Vector3(-FW * 0.5 - 1.5, 0.55, pz))
			_add_box(holder, Vector3(0.22, 1.1, 0.22), post_mat, Vector3(FW * 0.5 + 1.5, 0.55, pz))
		slot_labels.append(_add_label("أرض فارغة", c + Vector3(0, 3.8, FH * 0.5 + 4.0), 64))
		_make_crop_multimesh(plant, s)
		for i in NCELLS:
			_set_cell_soil(s, i, null)

	var mk := Node3D.new()
	mk.position = MARKET_POS
	add_child(mk)
	_add_box(mk, Vector3(10, 4, 8), _mat(Color(0.65, 0.4, 0.2)), Vector3(0, 2, 0))
	_add_box(mk, Vector3(11.5, 0.5, 9.5), _mat(Color(0.7, 0.15, 0.1)), Vector3(0, 4.25, 0))
	_add_box(mk, Vector3(3, 2.2, 0.2), _mat(Color(0.25, 0.15, 0.08)), Vector3(0, 1.1, 4.05))
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = MARKET_RANGE
	cm.bottom_radius = MARKET_RANGE
	cm.height = 0.05
	ring.mesh = cm
	ring.material_override = _mat(Color(1.0, 0.85, 0.2, 0.22))
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mk.add_child(ring)
	_add_label("السوق", Vector3(0, 7.5, 0), 80)


func _pv(st: SurfaceTool, v: Vector3, n: Vector3, r: float, a: float) -> void:
	st.set_normal(n)
	st.set_color(Color(r, 0.0, 0.0, a))
	st.add_vertex(v)


func _plant_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 4:
		var a := TAU * float(b) / 4.0 + 0.4
		var d := Vector3(cos(a), 0.0, sin(a))
		var p := Vector3(-d.z, 0.0, d.x)
		var base := d * 0.1
		var w := p * 0.045
		var mid := base + d * 0.04 + Vector3(0, 0.5, 0)
		var tip := base + d * 0.11 + Vector3(0, 1.0, 0)
		var n := (d * 0.4 + Vector3(0, 0.9, 0)).normalized()
		var l0 := base - w
		var r0 := base + w
		var l1 := mid - w * 0.7
		var r1 := mid + w * 0.7
		_pv(st, l0, n, 0.3, 0.0)
		_pv(st, r0, n, 0.3, 0.0)
		_pv(st, l1, n, 0.65, 0.0)
		_pv(st, r0, n, 0.3, 0.0)
		_pv(st, r1, n, 0.65, 0.0)
		_pv(st, l1, n, 0.65, 0.0)
		_pv(st, l1, n, 0.65, 0.0)
		_pv(st, r1, n, 0.65, 0.0)
		_pv(st, tip, n, 1.0, 0.0)
		# السنبلة
		var bot := tip - Vector3(0, 0.22, 0)
		var ear := tip - Vector3(0, 0.1, 0)
		var e1 := p * 0.07
		var e2 := d * 0.07
		_pv(st, bot, n, 1.0, 1.0)
		_pv(st, ear - e1, n, 1.0, 1.0)
		_pv(st, ear + e1, n, 1.0, 1.0)
		_pv(st, ear - e1, n, 1.0, 1.0)
		_pv(st, tip, n, 1.0, 1.0)
		_pv(st, ear + e1, n, 1.0, 1.0)
		_pv(st, bot, n, 1.0, 1.0)
		_pv(st, ear - e2, n, 1.0, 1.0)
		_pv(st, ear + e2, n, 1.0, 1.0)
		_pv(st, ear - e2, n, 1.0, 1.0)
		_pv(st, tip, n, 1.0, 1.0)
		_pv(st, ear + e2, n, 1.0, 1.0)
	return st.commit()


func _make_crop_multimesh(plant: Mesh, slot: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plant
	mm.instance_count = NCELLS * TUFTS
	mm.custom_aabb = AABB(Vector3(-FW * 0.5 - 2.0, -1.0, -FH * 0.5 - 2.0), Vector3(FW + 4.0, 5.0, FH + 4.0))
	var c := slot_center(slot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + slot
	for i in NCELLS:
		var cp := _cell_pos(slot, i) - c
		for t in TUFTS:
			var tc := t % TUFT_COLS
			var tr := floori(float(t) / TUFT_COLS)
			var x := ((float(tc) + 0.5) / TUFT_COLS - 0.5) * 4.4 + rng.randf_range(-0.22, 0.22)
			var z := ((float(tr) + 0.5) / TUFT_ROWS - 0.5) * 3.8 + rng.randf_range(-0.2, 0.2)
			var idx := i * TUFTS + t
			mm.set_instance_transform(idx, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp + Vector3(x, 0.2, z)))
			mm.set_instance_custom_data(idx, Color(0, 1, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = crop_mat
	mi.position = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0
	add_child(mi)
	crop_mms.append(mm)
	crop_nodes.append(mi)


func _in_lot(x: float, z: float, margin: float) -> bool:
	var col := roundi(x / LOT_DX) + 2
	var row := roundi(z / LOT_DZ + 1.5)
	if col < 0 or col >= SLOTS_X or row < 0 or row >= 4:
		return false
	var c := slot_center(row * SLOTS_X + col)
	return absf(x - c.x) < FW * 0.5 + margin and absf(z - c.z) < FH * 0.5 + margin


func _on_road(x: float, z: float, margin: float) -> bool:
	var dx := absf(fposmod(x, 70.0) - 35.0)
	var mz := fposmod(z, 60.0)
	var dz := minf(mz, 60.0 - mz)
	return dx < margin or dz < margin


func _free_spot(rng: RandomNumberGenerator, lot_m: float, road_m: float, mk_r: float) -> Variant:
	for t in 10:
		var x := rng.randf_range(-215.0, 215.0)
		var z := rng.randf_range(-165.0, 165.0)
		if _in_lot(x, z, lot_m) or _on_road(x, z, road_m):
			continue
		if Vector2(x, z).length() < mk_r:
			continue
		return Vector2(x, z)
	return null


func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 6:
		var a := TAU * float(b) / 6.0 + float(b) * 0.7
		var d := Vector3(cos(a), 0.0, sin(a))
		var p := Vector3(-d.z, 0.0, d.x)
		var tip := d * 0.28 + Vector3(0, 0.7 + 0.12 * float(b % 3), 0)
		var l := d * 0.12 - p * 0.05
		var r := d * 0.12 + p * 0.05
		st.set_normal(Vector3.UP)
		st.set_color(Color(0.8, 0.8, 0.8))
		st.add_vertex(l)
		st.set_normal(Vector3.UP)
		st.set_color(Color(0.8, 0.8, 0.8))
		st.add_vertex(r)
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1))
		st.add_vertex(tip)
	return st.commit()


func _build_scenery() -> void:
	add_child(scenery)
	scenery.add_child(grass_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	# عشب: مقاطع مكانية لتقليل الرسم عند البعد
	var gmesh := _grass_mesh()
	var gsh := Shader.new()
	gsh.code = GRASS_SHADER
	var gmat := ShaderMaterial.new()
	gmat.shader = gsh
	var chunks := {}
	for n in 8000:
		var sp: Variant = _free_spot(rng, 3.0, 5.2, 16.0)
		if sp == null:
			continue
		var v: Vector2 = sp
		var key := Vector2i(floori(v.x / 55.0), floori(v.y / 55.0))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(v)
	for key in chunks:
		var pts: Array = chunks[key]
		var center := Vector3((key.x + 0.5) * 55.0, 0.0, (key.y + 0.5) * 55.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = gmesh
		mm.instance_count = pts.size()
		for i in pts.size():
			var pv: Vector2 = pts[i]
			var sc := rng.randf_range(0.5, 1.2)
			var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.4), sc))
			mm.set_instance_transform(i, Transform3D(bs, Vector3(pv.x, 0.0, pv.y) - center))
			var tint := Color(0.15, 0.32, 0.08).lerp(Color(0.4, 0.46, 0.16), rng.randf())
			mm.set_instance_color(i, tint)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = gmat
		mi.position = center
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 110.0
		grass_root.add_child(mi)
	# أشجار
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.34
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radius = 1.0
	leaf_mesh.height = 2.0
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 5
	var spots: Array = []
	for n in 260:
		var sp: Variant = _free_spot(rng, 9.0, 8.0, 26.0)
		if sp != null:
			spots.append(sp)
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.use_colors = true
	trunks.mesh = trunk_mesh
	trunks.instance_count = spots.size()
	var leaves := MultiMesh.new()
	leaves.transform_format = MultiMesh.TRANSFORM_3D
	leaves.use_colors = true
	leaves.mesh = leaf_mesh
	leaves.instance_count = spots.size() * 3
	for i in spots.size():
		var pv: Vector2 = spots[i]
		var sc := rng.randf_range(0.8, 1.6)
		trunks.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(pv.x, 1.5 * sc, pv.y)))
		trunks.set_instance_color(i, Color(0.24, 0.16, 0.09).lerp(Color(0.16, 0.1, 0.06), rng.randf()))
		var lcol := Color(0.08, 0.24, 0.06).lerp(Color(0.16, 0.34, 0.09), rng.randf())
		for bi in 3:
			var off := Vector3.ZERO
			if bi == 1:
				off = Vector3(1.2, -0.5, 0.6)
			elif bi == 2:
				off = Vector3(-1.0, -0.3, -0.9)
			var sz := sc * rng.randf_range(1.5, 2.2) * (1.0 if bi == 0 else 0.8)
			var lb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.8, 1.1), sz))
			leaves.set_instance_transform(i * 3 + bi, Transform3D(lb, Vector3(pv.x, 3.8 * sc, pv.y) + off * sc))
			leaves.set_instance_color(i * 3 + bi, lcol.darkened(0.08 * float(bi)))
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 1.0
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = trunks
	tmi.material_override = tmat
	scenery.add_child(tmi)
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = leaves
	lmi.material_override = tmat
	scenery.add_child(lmi)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.tool_names = TOOL_NAMES
	hud.quality_names = QUALITY_NAMES
	hud.font = ui_font
	layer.add_child(hud)
	hud.tool_pressed.connect(_on_tool)
	hud.crop_pressed.connect(_on_crop)
	hud.sell_pressed.connect(_on_sell)
	hud.sound_pressed.connect(_on_sound)
	hud.quality_pressed.connect(_on_quality)


# ---------------------------------------------------------------- الصوت والجودة
func _setup_audio() -> void:
	_audio = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_audio.stream = gen
	_audio.volume_db = -8.0
	add_child(_audio)
	_audio.play()
	_audio_pb = _audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_audio() -> void:
	if _audio_pb == null:
		return
	var n := _audio_pb.get_frames_available()
	if n <= 0:
		return
	var lvl := clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) + (0.15 if tool_idx >= 0 else 0.0)
	var f := 26.0 + lvl * 40.0
	var vol := (0.16 + lvl * 0.12) if sound_on else 0.0
	var step := TAU * f / 22050.0
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_eng_phase += step
		if _eng_phase > TAU:
			_eng_phase -= TAU
		var s := sin(_eng_phase) + 0.55 * sin(2.0 * _eng_phase + 0.7) + 0.35 * sin(3.0 * _eng_phase + 1.9) + 0.2 * sin(5.0 * _eng_phase)
		s *= 0.75 + 0.25 * sin(_eng_phase * 0.5)
		s += randf_range(-0.12, 0.12)
		buf[i] = Vector2(s, s) * vol * 0.5
	_audio_pb.push_buffer(buf)


func _apply_quality() -> void:
	sun.shadow_enabled = quality > 0
	sun.directional_shadow_max_distance = 110.0 if quality >= 2 else 60.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality >= 2 else 2048, true)
	grass_root.visible = quality > 0
	var vr := 55.0 if quality == 0 else (100.0 if quality == 1 else 150.0)
	for n in crop_nodes:
		(n as GeometryInstance3D).visibility_range_end = vr
	dust_on = quality > 0
	get_viewport().msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED


func _on_quality() -> void:
	quality = (quality + 1) % 3
	_apply_quality()
	_save_prefs()
	_toast("الجودة: " + QUALITY_NAMES[quality])


func _on_sound() -> void:
	sound_on = not sound_on
	_save_prefs()


# ---------------------------------------------------------------- الهوية والحفظ
func _rand_id() -> String:
	var s := ""
	for i in 10:
		s += "abcdefghijklmnopqrstuvwxyz0123456789"[randi() % 36]
	return s


func _load_identity() -> void:
	var cf := ConfigFile.new()
	cf.load("user://player.cfg")
	my_id = str(cf.get_value("p", "id", ""))
	if my_id == "":
		my_id = _rand_id()
	my_name = str(cf.get_value("p", "name", ""))
	if my_name == "":
		my_name = "مزارع%d" % (randi() % 900 + 100)
	quality = clampi(int(cf.get_value("p", "quality", 1)), 0, 2)
	sound_on = bool(cf.get_value("p", "sound", true))
	_save_prefs()


func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "id", my_id)
	cf.set_value("p", "name", my_name)
	cf.set_value("p", "quality", quality)
	cf.set_value("p", "sound", sound_on)
	cf.save("user://player.cfg")


func _save_local() -> void:
	var f := FileAccess.open("user://farm.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"slot": my_slot, "farm": my_farm.to_dict()}))


func _load_local() -> Dictionary:
	if not FileAccess.file_exists("user://farm.json"):
		return {}
	var f := FileAccess.open("user://farm.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- الشبكة (Firebase REST)
func _db(method: int, path: String, body: String = "") -> Dictionary:
	if not net_on:
		return {"ok": false, "data": null}
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(base_url + "/" + path + ".json", headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "data": null}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {"ok": false, "data": null}
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": true, "data": JSON.parse_string(text)}


func _join() -> void:
	var loc := _load_local()
	my_slot = int(loc.get("slot", -1))
	if loc.has("farm"):
		my_farm.load_dict(loc["farm"])
	if net_on:
		var pr: Dictionary = await _db(HTTPClient.METHOD_GET, "players")
		if pr["ok"]:
			var used := {}
			var mine := -1
			if pr["data"] is Dictionary:
				for k in pr["data"]:
					var v = pr["data"][k]
					if v is Dictionary:
						var sl := int(v.get("slot", -1))
						if k == my_id:
							mine = sl
						elif sl >= 0:
							used[sl] = true
			if mine >= 0:
				my_slot = mine
			else:
				my_slot = -1
				for s in NSLOTS:
					if not used.has(s):
						my_slot = s
						break
				if my_slot < 0:
					my_slot = 0
					_toast("السيرفر ممتلئ")
			var fr: Dictionary = await _db(HTTPClient.METHOD_GET, "farms/" + my_id)
			if fr["ok"] and fr["data"] is Dictionary:
				my_farm.load_dict(fr["data"])
			connected = true
	if my_slot < 0 or my_slot >= NSLOTS:
		my_slot = 0
	_save_local()


func _spawn_me() -> void:
	me_pos = slot_center(my_slot) + Vector3(0, 0, FH * 0.5 + 8.0)
	yaw = 0.0
	cam_yaw = 0.0
	me = Tractor.new()
	add_child(me)
	me.build(Color(0.12, 0.42, 0.08), my_name, ui_font, dust_mat)
	me.position = me_pos
	slot_owner[my_slot] = my_id
	names[my_id] = my_name


func _push_me() -> void:
	_pushing = true
	var body := JSON.stringify({
		"name": my_name,
		"slot": my_slot,
		"x": snappedf(me_pos.x, 0.1),
		"z": snappedf(me_pos.z, 0.1),
		"ry": snappedf(yaw, 0.01),
		"t": {".sv": "timestamp"},
	})
	var r: Dictionary = await _db(HTTPClient.METHOD_PUT, "players/" + my_id, body)
	connected = r["ok"]
	_pushing = false


func _poll_players() -> void:
	_polling = true
	var r: Dictionary = await _db(HTTPClient.METHOD_GET, "players")
	if r["ok"]:
		connected = true
		_apply_players(r["data"])
	else:
		connected = false
	_polling = false


func _apply_players(data: Variant) -> void:
	var owners: Array = []
	owners.resize(NSLOTS)
	owners.fill("")
	var best := {}
	var seen := {}
	if data is Dictionary:
		var server_now := 0.0
		if data.has(my_id) and data[my_id] is Dictionary:
			server_now = float(data[my_id].get("t", 0))
		for k in data:
			var v = data[k]
			if not (v is Dictionary):
				continue
			var sl := int(v.get("slot", -1))
			var t := float(v.get("t", 0))
			var nm := str(v.get("name", "؟"))
			names[k] = nm
			if sl >= 0 and sl < NSLOTS:
				if not best.has(sl) or t > best[sl]:
					best[sl] = t
					owners[sl] = k
			if k == my_id:
				continue
			if server_now > 0.0 and server_now - t > 60000.0:
				continue
			seen[k] = true
			var tx := float(v.get("x", 0))
			var tz := float(v.get("z", 0))
			var ty := float(v.get("ry", 0))
			if not others.has(k):
				var tr := Tractor.new()
				add_child(tr)
				tr.build(_color_for(k), nm, ui_font, dust_mat)
				tr.position = Vector3(tx, 0, tz)
				tr.rotation.y = ty
				others[k] = {"node": tr, "tx": tx, "tz": tz, "ty": ty}
			else:
				var o: Dictionary = others[k]
				o["tx"] = tx
				o["tz"] = tz
				o["ty"] = ty
				(o["node"] as Tractor).set_label(nm)
	for k in others.keys():
		if not seen.has(k):
			(others[k]["node"] as Node3D).queue_free()
			others.erase(k)
	owners[my_slot] = my_id
	for s in NSLOTS:
		if owners[s] != slot_owner[s]:
			slot_owner[s] = owners[s]
			_refresh_slot(s)
		_update_slot_visual(s)


func _poll_farms() -> void:
	_farm_polling = true
	var r: Dictionary = await _db(HTTPClient.METHOD_GET, "farms")
	if r["ok"]:
		_apply_farms(r["data"])
	_farm_polling = false


func _apply_farms(data: Variant) -> void:
	if not (data is Dictionary):
		return
	for k in data:
		if k == my_id:
			continue
		var f := FarmData.new()
		f.load_dict(data[k])
		var sig := JSON.stringify(f.to_dict())
		if farm_sigs.get(k, "") == sig:
			continue
		farm_sigs[k] = sig
		farms[k] = f
		for s in NSLOTS:
			if slot_owner[s] == k:
				_refresh_slot(s)


func _push_farm() -> void:
	if not net_on:
		return
	_pushing_farm = true
	await _db(HTTPClient.METHOD_PUT, "farms/" + my_id, JSON.stringify(my_farm.to_dict()))
	_pushing_farm = false


func _color_for(id: String) -> Color:
	return Color.from_hsv(float(absi(hash(id)) % 360) / 360.0, 0.65, 0.6)


# ---------------------------------------------------------------- الخلايا والمزارع
func _cell_pos(slot: int, i: int) -> Vector3:
	var cx := i % COLS
	var cz := floori(float(i) / COLS)
	return slot_center(slot) + Vector3((cx - (COLS - 1) * 0.5) * CELL, 0.0, (cz - (ROWS - 1) * 0.5) * CELL)


func _set_cell_soil(slot: int, i: int, f: FarmData) -> void:
	var idx := slot * NCELLS + i
	var p := _cell_pos(slot, i)
	var st := 0
	if f != null:
		st = f.st[i]
	soil_mm.set_instance_transform(idx, Transform3D(Basis(), p + Vector3(0, 0.1, 0)))
	soil_mm.set_instance_color(idx, SOIL_RAW if st == 0 else SOIL_PLOWED)


func _set_cell_crop(slot: int, i: int, f: FarmData, _now: float) -> void:
	var mm := crop_mms[slot] as MultiMesh
	var data := Color(0, 1, 0, 0)
	if f != null and f.st[i] == 2:
		data = Color(float(f.pt[i] - time_base), float(CROPS[f.cr[i]]["grow"]), float(f.cr[i]), 1.0)
	var base := i * TUFTS
	for t in TUFTS:
		mm.set_instance_custom_data(base + t, data)


func _set_cell(slot: int, i: int, f: FarmData, now: float) -> void:
	_set_cell_soil(slot, i, f)
	_set_cell_crop(slot, i, f, now)


func _farm_for_slot(s: int) -> FarmData:
	var o: String = slot_owner[s]
	if o == "":
		return null
	if o == my_id:
		return my_farm
	return farms.get(o, null)


func _refresh_slot(s: int) -> void:
	var now := Time.get_unix_time_from_system()
	var f := _farm_for_slot(s)
	for i in NCELLS:
		_set_cell(s, i, f, now)


func _refresh_all() -> void:
	for s in NSLOTS:
		_refresh_slot(s)


func _update_slot_visual(s: int) -> void:
	var o: String = slot_owner[s]
	var l := slot_labels[s] as Label3D
	var m := slot_mats[s] as StandardMaterial3D
	var text := ""
	if o == "":
		text = "أرض فارغة"
		m.albedo_color = Color(1, 1, 1, 0.35)
	elif o == my_id:
		text = "مزرعتك"
		m.albedo_color = Color(1.0, 0.75, 0.1, 0.9)
	else:
		text = "مزرعة " + str(names.get(o, "؟"))
		m.albedo_color = Color(1, 1, 1, 0.8)
	if l.text != text:
		l.text = text


func _cell_at(p: Vector3, slot: int) -> int:
	var c := slot_center(slot)
	var lx := p.x - c.x + FW * 0.5
	var lz := p.z - c.z + FH * 0.5
	if lx < 0.0 or lz < 0.0:
		return -1
	var cx := int(lx / CELL)
	var cz := int(lz / CELL)
	if cx >= COLS or cz >= ROWS:
		return -1
	return cz * COLS + cx


func _apply_tool() -> void:
	if tool_idx < 0:
		return
	var reach := -3.4 if tool_idx == 2 else 2.9
	var spot := me_pos + Vector3(sin(yaw), 0.0, cos(yaw)) * reach
	var i := _cell_at(spot, my_slot)
	if i < 0:
		return
	var now := Time.get_unix_time_from_system()
	var f := my_farm
	var changed := false
	match tool_idx:
		0:
			if f.st[i] == 0:
				f.st[i] = 1
				changed = true
		1:
			if f.st[i] == 1:
				f.st[i] = 2
				f.cr[i] = crop_idx
				f.pt[i] = now
				changed = true
		2:
			if f.st[i] == 2 and now - f.pt[i] >= float(CROPS[f.cr[i]]["grow"]):
				f.inv[f.cr[i]] += YIELD_PER_CELL
				f.st[i] = 1
				changed = true
	if changed:
		_set_cell(my_slot, i, f, now)
		dirty = true


# ---------------------------------------------------------------- الأزرار
func _toast(t: String) -> void:
	msg = t
	msg_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _on_tool(i: int) -> void:
	tool_idx = -1 if tool_idx == i else i
	if me != null:
		me.set_tool(tool_idx)


func _on_crop() -> void:
	crop_idx = (crop_idx + 1) % CROPS.size()


func _on_sell() -> void:
	if me_pos.distance_to(MARKET_POS) >= MARKET_RANGE:
		return
	var total := 0
	for i in 4:
		total += int(my_farm.inv[i]) * int(CROPS[i]["price"])
		my_farm.inv[i] = 0
	if total > 0:
		my_farm.coins += total
		dirty = true
		_toast("بعت المحاصيل بـ %d عملة" % total)
	else:
		_toast("لا يوجد شيء للبيع")


# ---------------------------------------------------------------- الحلقة الرئيسية
func _process(delta: float) -> void:
	_day_cd -= delta
	if _day_cd <= 0.0:
		_day_cd = 0.25
		_update_daylight()
	if crop_mat != null:
		crop_mat.set_shader_parameter("now_rel", Time.get_unix_time_from_system() - time_base)
	if clouds != null and cam != null:
		clouds.position = Vector3(cam.position.x, 260.0, cam.position.z)
	if not ready_to_play:
		return
	_drive(delta)
	_follow_camera(delta)
	_apply_tool()
	_smooth_others(delta)
	_timers(delta)
	_fill_audio()
	_update_hud()


func _update_daylight() -> void:
	var tod := fposmod(Time.get_unix_time_from_system() / DAY_SECONDS, 1.0)
	if force_tod >= 0.0:
		tod = force_tod
	var h := sin(tod * TAU)
	var day := clampf(h * 2.0 + 0.4, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(h) * 4.0, 0.0, 1.0)
	sun.rotation_degrees = Vector3(-tod * 360.0, -35.0, 0.0)
	sun.light_energy = clampf(h * 1.5, 0.0, 1.05)
	var warm := clampf(1.0 - h * 2.5, 0.0, 1.0) if h > 0.0 else 1.0
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.55, 0.28), warm)
	var top := Color(0.01, 0.015, 0.05).lerp(Color(0.22, 0.45, 0.85), day)
	var hor := Color(0.04, 0.05, 0.12).lerp(Color(0.68, 0.8, 0.92), day).lerp(Color(0.95, 0.5, 0.25), dusk * 0.65)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = Color(0.1, 0.14, 0.08).lerp(Color(0.2, 0.3, 0.15), day)
	env.fog_light_color = hor
	var ctint := Color(0.06, 0.07, 0.12).lerp(Color(1, 1, 1), day).lerp(Color(1.0, 0.7, 0.5), dusk * 0.5)
	clouds_mat.set_shader_parameter("tint", Vector3(ctint.r, ctint.g, ctint.b))
	env.ambient_light_energy = lerpf(0.25, 0.6, day)
	var hour := fposmod(6.0 + tod * 24.0, 24.0)
	time_text = "%02d:%02d" % [int(hour), int((hour - floorf(hour)) * 60.0)]


func _drive(delta: float) -> void:
	var inp := hud.stick
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb.length() > 0.1:
		inp = kb
	var target := -inp.y * MAX_SPEED
	if target < 0.0:
		target *= 0.5
	speed = move_toward(speed, target, ACCEL * delta)
	steer_in = inp.x
	yaw -= inp.x * TURN_RATE * clampf(speed / 4.0, -1.0, 1.0) * delta
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	me_pos += fwd * speed * delta
	me_pos.x = clampf(me_pos.x, -215.0, 215.0)
	me_pos.z = clampf(me_pos.z, -165.0, 165.0)
	me.position = me_pos
	me.rotation.y = yaw
	me.spin(speed * delta)
	me.update_motion(speed, steer_in, delta, dust_on)


func _follow_camera(delta: float) -> void:
	cam_yaw = lerp_angle(cam_yaw, yaw, clampf(delta * 3.0, 0.0, 1.0))
	var back := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	cam.position = me_pos + back * 12.0 + Vector3(0, 6.5, 0)
	cam.look_at(me_pos + Vector3(0, 1.8, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 66.0 + absf(speed) * 0.9, clampf(delta * 3.0, 0.0, 1.0))


func _smooth_others(delta: float) -> void:
	var k := clampf(delta * 6.0, 0.0, 1.0)
	for id in others:
		var o: Dictionary = others[id]
		var n := o["node"] as Tractor
		var old := n.position
		var old_yaw := n.rotation.y
		n.position = old.lerp(Vector3(o["tx"], 0.0, o["tz"]), k)
		n.rotation.y = lerp_angle(old_yaw, float(o["ty"]), k)
		var d := n.position - old
		var dir := 1.0 if d.dot(-n.basis.z) >= 0.0 else -1.0
		n.spin(d.length() * dir)
		var spd := d.length() / maxf(delta, 0.001) * dir
		var yrate := angle_difference(old_yaw, n.rotation.y) / maxf(delta, 0.001)
		var st := clampf(-yrate / (TURN_RATE * maxf(absf(clampf(spd / 4.0, -1.0, 1.0)), 0.3)), -1.0, 1.0)
		n.update_motion(spd, st, delta, dust_on)


func _timers(delta: float) -> void:
	if net_on:
		_push_cd -= delta
		if _push_cd <= 0.0 and not _pushing:
			_push_cd = 0.5
			_push_me()
		_poll_cd -= delta
		if _poll_cd <= 0.0 and not _polling:
			_poll_cd = 0.5
			_poll_players()
		_farm_poll_cd -= delta
		if _farm_poll_cd <= 0.0 and not _farm_polling:
			_farm_poll_cd = 3.0
			_poll_farms()
	_save_cd -= delta
	if dirty and _save_cd <= 0.0 and not _pushing_farm:
		_save_cd = 1.5
		dirty = false
		_save_local()
		_push_farm()


func _update_hud() -> void:
	var parts := PackedStringArray()
	for i in 4:
		if int(my_farm.inv[i]) > 0:
			parts.append("%s:%d" % [CROPS[i]["n"], my_farm.inv[i]])
	var status := "فردي (بدون سيرفر)"
	if net_on:
		status = ("متصل · %d لاعب" % (others.size() + 1)) if connected else "غير متصل"
	var now_s := Time.get_ticks_msec() / 1000.0
	hud.info = {
		"coins": my_farm.coins,
		"tool": tool_idx,
		"crop": CROPS[crop_idx]["n"],
		"near_market": me_pos.distance_to(MARKET_POS) < MARKET_RANGE,
		"inv": "المخزن: " + ("  ".join(parts) if parts.size() > 0 else "فارغ"),
		"time": time_text,
		"status": status,
		"msg": msg if now_s < msg_until else "",
		"sound": sound_on,
		"quality": quality,
	}
	hud.queue_redraw()
