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
const SOIL_RAW := Color(0.45, 0.55, 0.22)
const SOIL_PLOWED := Color(0.33, 0.2, 0.1)
const CROPS := [
	{"n": "قمح", "grow": 40.0, "price": 12, "c": Color(0.93, 0.78, 0.25)},
	{"n": "شعير", "grow": 30.0, "price": 10, "c": Color(0.78, 0.82, 0.35)},
	{"n": "ذرة", "grow": 70.0, "price": 18, "c": Color(0.95, 0.85, 0.2)},
	{"n": "كانولا", "grow": 55.0, "price": 15, "c": Color(1.0, 0.9, 0.1)},
]
const TOOL_NAMES := ["محراث", "بذّار", "حصّادة"]
const TOOL_COLORS := [Color(0.35, 0.35, 0.4), Color(0.2, 0.4, 0.9), Color(0.9, 0.25, 0.15)]


# ---------------------------------------------------------------- بيانات المزرعة
class FarmData:
	const N := 48
	var st := PackedInt32Array()
	var cr := PackedInt32Array()
	var pt := PackedFloat64Array()
	var inv := [0, 0, 0, 0]
	var coins := 0

	func _init() -> void:
		st.resize(N)
		cr.resize(N)
		pt.resize(N)

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
		coins = int(d.get("c", 0))
		var iv := str(d.get("i", "")).split(",")
		for k in range(mini(iv.size(), 4)):
			inv[k] = int(iv[k])


# ---------------------------------------------------------------- الجرار
class Tractor:
	extends Node3D
	var _wheels: Array = []
	var _tool: MeshInstance3D
	var _tool_mat: StandardMaterial3D
	var _label: Label3D

	func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		mi.material_override = m
		mi.position = pos
		parent.add_child(mi)
		return mi

	func _wheel(pos: Vector3, radius: float, width: float) -> void:
		var pivot := Node3D.new()
		pivot.position = pos
		add_child(pivot)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = width
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.08, 0.08)
		mi.material_override = m
		mi.rotation_degrees = Vector3(0, 0, 90)
		pivot.add_child(mi)
		_box(pivot, Vector3(width + 0.06, 0.18, 0.35), Color(0.55, 0.55, 0.55), Vector3(0, radius, 0))
		_wheels.append([pivot, radius])

	func build(color: Color, label_text: String, font: Font) -> void:
		_box(self, Vector3(2.0, 0.8, 3.4), color, Vector3(0, 1.0, 0))
		_box(self, Vector3(1.7, 0.7, 1.4), color.darkened(0.2), Vector3(0, 1.75, -0.9))
		_box(self, Vector3(1.8, 1.5, 1.5), Color(0.75, 0.85, 0.95), Vector3(0, 2.2, 0.6))
		for sx in [-1.2, 1.2]:
			_wheel(Vector3(sx, 0.85, 1.0), 0.85, 0.55)
			_wheel(Vector3(sx, 0.5, -1.2), 0.5, 0.4)
		_tool = _box(self, Vector3(2.6, 0.35, 1.0), Color(0.3, 0.3, 0.3), Vector3(0, 0.6, 2.9))
		_tool_mat = _tool.material_override as StandardMaterial3D
		_tool.visible = false
		_label = Label3D.new()
		_label.text = label_text
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 56
		_label.pixel_size = 0.01
		_label.outline_size = 14
		_label.no_depth_test = true
		_label.position = Vector3(0, 4.4, 0)
		if font != null:
			_label.font = font
		add_child(_label)

	func set_label(t: String) -> void:
		if _label != null and _label.text != t:
			_label.text = t

	func set_tool(i: int, col: Color) -> void:
		if _tool == null:
			return
		_tool.visible = i >= 0
		if i >= 0:
			_tool_mat.albedo_color = col

	func spin(dist: float) -> void:
		for w in _wheels:
			(w[0] as Node3D).rotation.x -= dist / float(w[1])


# ---------------------------------------------------------------- واجهة اللمس
class Hud:
	extends Control
	signal tool_pressed(index: int)
	signal crop_pressed
	signal sell_pressed

	const STICK_R := 110.0

	var info: Dictionary = {}
	var stick := Vector2.ZERO
	var tool_names: Array = []
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
				else:
					sell_pressed.emit()
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
			if id < 3:
				label = str(tool_names[id])
				if int(info.get("tool", -1)) == id:
					col = Color(0.95, 0.7, 0.1, 0.9)
			elif id == 10:
				label = "المحصول: " + str(info.get("crop", ""))
				col = Color(0.1, 0.35, 0.15, 0.85)
			else:
				if not info.get("near_market", false):
					continue
				label = "بيع المحاصيل"
				col = Color(0.15, 0.5, 0.2, 0.9)
			_panel(r, col)
			_t(f, label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 9.0), 26, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ---------------------------------------------------------------- الحالة
var net_on := false
var base_url := ""
var my_id := ""
var my_name := ""
var my_slot := 0
var my_farm := FarmData.new()
var farms := {}
var others := {}
var names := {}
var slot_owner: Array = []
var me: Tractor
var me_pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var cam: Camera3D
var cam_yaw := 0.0
var sun: DirectionalLight3D
var env: Environment
var soil_mm: MultiMesh
var crop_mm: MultiMesh
var hud: Hud
var ui_font: Font
var tool_idx := -1
var crop_idx := 0
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
var _grow_cd := 0.0
var _pushing := false
var _polling := false
var _farm_polling := false
var _pushing_farm := false


func _ready() -> void:
	randomize()
	base_url = DB_URL.strip_edges().rstrip("/")
	net_on = base_url.begins_with("https://")
	slot_owner.resize(NSLOTS)
	slot_owner.fill("")
	if ResourceLoader.exists("res://Tajawal-Bold.ttf"):
		ui_font = load("res://Tajawal-Bold.ttf") as Font
	_build_environment()
	_build_world()
	_build_hud()
	_load_identity()
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


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 600.0
	add_child(cam)


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = NSLOTS * NCELLS
	mm.custom_aabb = AABB(Vector3(-260, -5, -200), Vector3(520, 30, 400))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	return mm


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(440, 340)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.28, 0.55, 0.25))
	add_child(ground)

	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(4.6, 0.2, 4.6)
	soil_mm = _make_multimesh(soil_mesh)
	var crop_mesh := BoxMesh.new()
	crop_mesh.size = Vector3(1, 1, 1)
	crop_mm = _make_multimesh(crop_mesh)

	for s in NSLOTS:
		var c := slot_center(s)
		var mat := _mat(Color(1, 1, 1, 0.55))
		slot_mats.append(mat)
		var holder := Node3D.new()
		holder.position = c
		add_child(holder)
		_add_box(holder, Vector3(FW + 3.0, 0.6, 0.4), mat, Vector3(0, 0.3, -FH * 0.5 - 1.5))
		_add_box(holder, Vector3(FW + 3.0, 0.6, 0.4), mat, Vector3(0, 0.3, FH * 0.5 + 1.5))
		_add_box(holder, Vector3(0.4, 0.6, FH + 3.0), mat, Vector3(-FW * 0.5 - 1.5, 0.3, 0))
		_add_box(holder, Vector3(0.4, 0.6, FH + 3.0), mat, Vector3(FW * 0.5 + 1.5, 0.3, 0))
		slot_labels.append(_add_label("أرض فارغة", c + Vector3(0, 3.8, FH * 0.5 + 4.0), 64))
		for i in NCELLS:
			_set_cell(s, i, null, 0.0)

	var mk := Node3D.new()
	mk.position = MARKET_POS
	add_child(mk)
	_add_box(mk, Vector3(10, 4, 8), _mat(Color(0.65, 0.4, 0.2)), Vector3(0, 2, 0))
	_add_box(mk, Vector3(11.5, 0.5, 9.5), _mat(Color(0.7, 0.15, 0.1)), Vector3(0, 4.25, 0))
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = MARKET_RANGE
	cm.bottom_radius = MARKET_RANGE
	cm.height = 0.05
	ring.mesh = cm
	ring.material_override = _mat(Color(1.0, 0.85, 0.2, 0.25))
	ring.position = Vector3(0, 0.03, 0)
	mk.add_child(ring)
	_add_label("السوق", Vector3(0, 7.5, 0), 80)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.tool_names = TOOL_NAMES
	hud.font = ui_font
	layer.add_child(hud)
	hud.tool_pressed.connect(_on_tool)
	hud.crop_pressed.connect(_on_crop)
	hud.sell_pressed.connect(_on_sell)


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
		cf.set_value("p", "id", my_id)
	my_name = str(cf.get_value("p", "name", ""))
	if my_name == "":
		my_name = "مزارع%d" % (randi() % 900 + 100)
		cf.set_value("p", "name", my_name)
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
	me.build(Color(0.15, 0.6, 0.2), my_name, ui_font)
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
				tr.build(_color_for(k), nm, ui_font)
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
	for s in NSLOTS:
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
		farms[k] = f


func _push_farm() -> void:
	if not net_on:
		return
	_pushing_farm = true
	await _db(HTTPClient.METHOD_PUT, "farms/" + my_id, JSON.stringify(my_farm.to_dict()))
	_pushing_farm = false


func _color_for(id: String) -> Color:
	return Color.from_hsv(float(absi(hash(id)) % 360) / 360.0, 0.7, 0.9)


# ---------------------------------------------------------------- الخلايا والمزارع
func _cell_pos(slot: int, i: int) -> Vector3:
	var cx := i % COLS
	var cz := floori(float(i) / COLS)
	return slot_center(slot) + Vector3((cx - (COLS - 1) * 0.5) * CELL, 0.0, (cz - (ROWS - 1) * 0.5) * CELL)


func _set_cell(slot: int, i: int, f: FarmData, now: float) -> void:
	var idx := slot * NCELLS + i
	var p := _cell_pos(slot, i)
	var st := 0
	if f != null:
		st = f.st[i]
	soil_mm.set_instance_transform(idx, Transform3D(Basis(), p + Vector3(0, 0.1, 0)))
	soil_mm.set_instance_color(idx, SOIL_RAW if st == 0 else SOIL_PLOWED)
	if st == 2:
		var crop: Dictionary = CROPS[f.cr[i]]
		var g := clampf((now - f.pt[i]) / float(crop["grow"]), 0.0, 1.0)
		var h := 0.2 + g * 1.0
		var b := Basis().scaled(Vector3(3.9, h, 3.9))
		crop_mm.set_instance_transform(idx, Transform3D(b, p + Vector3(0, 0.2 + h * 0.5, 0)))
		var base_col: Color = crop["c"]
		crop_mm.set_instance_color(idx, Color(0.2, 0.55, 0.15).lerp(base_col, g))
	else:
		crop_mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), p))
		crop_mm.set_instance_color(idx, Color.WHITE)


func _farm_for_slot(s: int) -> FarmData:
	var o: String = slot_owner[s]
	if o == "":
		return null
	if o == my_id:
		return my_farm
	return farms.get(o, null)


func _refresh_all() -> void:
	var now := Time.get_unix_time_from_system()
	for s in NSLOTS:
		var f := _farm_for_slot(s)
		for i in NCELLS:
			_set_cell(s, i, f, now)


func _update_slot_visual(s: int) -> void:
	var o: String = slot_owner[s]
	var l := slot_labels[s] as Label3D
	var m := slot_mats[s] as StandardMaterial3D
	if o == "":
		l.text = "أرض فارغة"
		m.albedo_color = Color(1, 1, 1, 0.35)
	elif o == my_id:
		l.text = "مزرعتك"
		m.albedo_color = Color(1.0, 0.75, 0.1, 0.9)
	else:
		l.text = "مزرعة " + str(names.get(o, "؟"))
		m.albedo_color = Color(1, 1, 1, 0.8)


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
	var rear := me_pos + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.6
	var i := _cell_at(rear, my_slot)
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
		me.set_tool(tool_idx, TOOL_COLORS[maxi(tool_idx, 0)])


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
	_update_daylight()
	if not ready_to_play:
		return
	_drive(delta)
	_follow_camera(delta)
	_apply_tool()
	_smooth_others(delta)
	_timers(delta)
	_update_hud()


func _update_daylight() -> void:
	var tod := fposmod(Time.get_unix_time_from_system() / DAY_SECONDS, 1.0)
	if force_tod >= 0.0:
		tod = force_tod
	var h := sin(tod * TAU)
	var day := clampf(h * 2.0 + 0.4, 0.0, 1.0)
	sun.rotation_degrees = Vector3(-tod * 360.0, -35.0, 0.0)
	sun.light_energy = clampf(h * 1.6, 0.0, 1.2)
	env.background_color = Color(0.03, 0.04, 0.12).lerp(Color(0.5, 0.75, 0.95), day)
	env.ambient_light_color = Color(0.25, 0.3, 0.5).lerp(Color.WHITE, day)
	env.ambient_light_energy = lerpf(0.35, 0.65, day)
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
	yaw -= inp.x * TURN_RATE * clampf(speed / 4.0, -1.0, 1.0) * delta
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	me_pos += fwd * speed * delta
	me_pos.x = clampf(me_pos.x, -215.0, 215.0)
	me_pos.z = clampf(me_pos.z, -165.0, 165.0)
	me.position = me_pos
	me.rotation.y = yaw
	me.spin(speed * delta)


func _follow_camera(delta: float) -> void:
	cam_yaw = lerp_angle(cam_yaw, yaw, clampf(delta * 3.0, 0.0, 1.0))
	var back := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	cam.position = me_pos + back * 11.0 + Vector3(0, 6.5, 0)
	cam.look_at(me_pos + Vector3(0, 1.5, 0), Vector3.UP)


func _smooth_others(delta: float) -> void:
	var k := clampf(delta * 6.0, 0.0, 1.0)
	for id in others:
		var o: Dictionary = others[id]
		var n := o["node"] as Tractor
		var old := n.position
		n.position = old.lerp(Vector3(o["tx"], 0.0, o["tz"]), k)
		n.rotation.y = lerp_angle(n.rotation.y, float(o["ty"]), k)
		var d := n.position - old
		var dir := 1.0 if d.dot(-n.basis.z) >= 0.0 else -1.0
		n.spin(d.length() * dir)


func _timers(delta: float) -> void:
	_grow_cd -= delta
	if _grow_cd <= 0.0:
		_grow_cd = 1.0
		_refresh_all()
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
	}
	hud.queue_redraw()
