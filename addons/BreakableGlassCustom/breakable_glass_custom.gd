@tool
extends CSGPolygon3D

# NOTE: class_name is intentionally removed/commented out for this Addon version 
# to ensure it registers strictly via the plugin.gd script.
# class_name BreakableGlassCustom

# --- 1. CONFIGURATION ---

# [CHANGE] Set default depth for new instances
func _init():
	if depth == 1.0:
		depth = 0.1

# [CHANGE] Moved Buttons to the TOP so they appear first in the Inspector
@export_tool_button("Generate Preview", "Refresh") var action_generate = _preview
@export_tool_button("Clear Preview", "Clear") var action_clear = _clear

@export_group("Collision (Unbroken)")
## Layer for the unbroken window.
@export_flags_3d_physics var unbroken_collision_layer: int = 1:
	set(value):
		unbroken_collision_layer = value
		collision_layer = value
@export_flags_3d_physics var unbroken_collision_mask: int = 1:
	set(value):
		unbroken_collision_mask = value
		collision_mask = value

@export_group("Collision (Shards)")
## Layer for the broken shards.
@export_flags_3d_physics var broken_collision_layer: int = 1
@export_flags_3d_physics var broken_collision_mask: int = 1

@export_group("Fracture Settings")
@export var shard_mass: float = 1.0
@export var physics_material: PhysicsMaterial
@export var explosion_force: float = 5.0
@export var impact_point_preview: Vector2 = Vector2(0.0, 0.0):
	set(value):
		impact_point_preview = value
		if has_node("Preview"): _preview()

@export_group("Shard Lifetime")
@export var auto_despawn: bool = true
@export var despawn_time: float = 10.0

@export_group("Fracture Pattern")
@export_range(5.0, 90.0) var min_angle_deg: float = 15.0
@export_range(5.0, 90.0) var max_angle_deg: float = 45.0
@export_range(1, 10) var ring_count: int = 5
@export_range(0.0, 1.0) var ring_jitter: float = 0.1
@export_range(0.0, 45.0) var cut_angle_jitter: float = 5.0

# Internal variable to restore visibility state
var _original_layers: int = 1

# --- 2. PUBLIC API ---

func break_window(global_hit_pos: Vector3):
	var local_pos_3d = to_local(global_hit_pos)
	
	# Map 3D hit to 2D plane (CSGPolygon works on XY by default)
	var impact_2d = Vector2(local_pos_3d.x, local_pos_3d.y)
	var rect = _get_polygon_bounding_rect(polygon)
	impact_2d = impact_2d.clamp(rect.position, rect.end)

	spawn_shards(impact_2d, get_parent() if get_parent() else self, false)
	
	# Disable Self (Visuals + Collision)
	layers = 0 
	use_collision = false

# --- 3. LIFECYCLE ---

func _ready():
	# 1. Force Mode
	if mode != CSGPolygon3D.MODE_DEPTH:
		mode = CSGPolygon3D.MODE_DEPTH
	
	# 2. Force Collision ON
	use_collision = true
	collision_layer = unbroken_collision_layer
	collision_mask = unbroken_collision_mask
	
	# 3. Set Default Material if missing
	if material == null:
		material = _get_default_glass_material()
	
	# 4. Fix visuals
	path_interval = 1.0
	if not has_node("Preview"):
		layers = 1

# --- 4. PREVIEW SYSTEM ---

func _preview():
	_clear() # Clean up any existing preview first
	
	_original_layers = layers
	
	# Hide Unbroken Window
	layers = 0
	use_collision = false 
	
	var container = Node3D.new()
	container.name = "Preview"
	add_child(container)
	
	var rect = _get_polygon_bounding_rect(polygon)
	var safe_impact = impact_point_preview.clamp(rect.position, rect.end)
	
	spawn_shards(safe_impact, container, true)

func _clear():
	# [CHANGE] Robust cleanup loop.
	# Iterate through all children to find ANY node starting with "Preview".
	# This catches duplicates like "Preview2", "Preview3" if clicked fast.
	for child in get_children():
		if child.name.begins_with("Preview"):
			# 1. Detach immediately so Godot doesn't count it as a name conflict
			remove_child(child)
			# 2. Queue for deletion from memory
			child.queue_free()
	
	# Restore Unbroken Window
	layers = _original_layers
	if layers == 0: layers = 1
	
	use_collision = true
	collision_layer = unbroken_collision_layer
	collision_mask = unbroken_collision_mask

# --- 5. FRACTURE ALGORITHM ---

func spawn_shards(impact: Vector2, parent: Node, is_preview: bool):
	if polygon.size() < 3: return
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var safe_layer = 1
	if broken_collision_layer != null: safe_layer = int(broken_collision_layer)
	
	var safe_mask = 1
	if broken_collision_mask != null: safe_mask = int(broken_collision_mask)
	
	var rect = _get_polygon_bounding_rect(polygon)
	var max_dim = max(rect.size.x, rect.size.y)
	var max_dist = max_dim * 1.5 
	
	var global_ring_dists = []
	for r in range(ring_count):
		var t = float(r + 1) / float(ring_count + 1)
		t = pow(t, 0.8) 
		global_ring_dists.append(t * max_dist)
	
	var angles = []
	var current_deg = rng.randf_range(0, 360)
	var total_rot = 0.0
	while total_rot < 360.0:
		angles.append(deg_to_rad(current_deg))
		var step = rng.randf_range(min_angle_deg, max_angle_deg)
		if total_rot + step > 360.0: break
		current_deg += step
		total_rot += step
	angles.sort()
	
	for i in range(angles.size()):
		var ang_a = angles[i]
		var ang_b = angles[(i + 1) % angles.size()]
		if ang_b < ang_a: ang_b += TAU
		
		var dir_a = Vector2(cos(ang_a), sin(ang_a))
		var dir_b = Vector2(cos(ang_b), sin(ang_b))
		var bisector = (dir_a + dir_b).normalized()
		
		var cuts_data = []
		cuts_data.append({ "dist": 0.0, "normal": bisector })
		
		var prev_d = 0.0
		for base_d in global_ring_dists:
			var d = base_d + rng.randf_range(-1.0, 1.0) * (base_d * ring_jitter)
			if d <= prev_d + 0.05: d = prev_d + 0.05
			var jitter = deg_to_rad(rng.randf_range(-cut_angle_jitter, cut_angle_jitter))
			var n = bisector.rotated(jitter)
			cuts_data.append({ "dist": d, "normal": n })
			prev_d = d
			
		cuts_data.append({ "dist": max_dist * 1.5, "normal": bisector })
		
		for k in range(cuts_data.size() - 1):
			var cut_near = cuts_data[k]
			var cut_far  = cuts_data[k+1]
			
			var center_near = impact + (bisector * cut_near.dist)
			var center_far  = impact + (bisector * cut_far.dist)
			
			var p_near_a = _intersect_ray_plane(impact, dir_a, center_near, cut_near.normal)
			var p_near_b = _intersect_ray_plane(impact, dir_b, center_near, cut_near.normal)
			var p_far_a  = _intersect_ray_plane(impact, dir_a, center_far, cut_far.normal)
			var p_far_b  = _intersect_ray_plane(impact, dir_b, center_far, cut_far.normal)
			
			var raw_poly = PackedVector2Array([p_near_a, p_far_a, p_far_b, p_near_b])
			var clipped = Geometry2D.intersect_polygons(raw_poly, polygon)
			
			for poly in clipped:
				_build_shard_object(poly, parent, is_preview, rng, impact, safe_layer, safe_mask)

func _build_shard_object(poly: PackedVector2Array, parent: Node, is_preview: bool, rng: RandomNumberGenerator, impact: Vector2, layer: int, mask: int):
	if poly.size() < 3: return
	
	var mesh = _poly_to_mesh(poly, depth) 
	if not mesh: return
	
	var rb = RigidBody3D.new()
	rb.mass = shard_mass
	rb.collision_layer = layer
	rb.collision_mask = mask
	if physics_material: rb.physics_material_override = physics_material
	
	if is_preview: rb.transform = Transform3D.IDENTITY
	else: rb.global_transform = global_transform
	
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	
	# Use self.material to ensure shards inherit the main glass material (default or custom)
	mi.material_override = material 
	mi.layers = 1 
	rb.add_child(mi)
	
	var col = CollisionShape3D.new()
	var shape = ConvexPolygonShape3D.new()
	shape.points = mesh.get_faces()
	col.shape = shape; col.visible = false
	rb.add_child(col)
	
	if Engine.is_editor_hint(): 
		parent.add_child(rb)
	else:
		parent.call_deferred("add_child", rb)

	if is_preview:
		rb.freeze = true
	else:
		var center_2d = Vector2.ZERO
		for p in poly: center_2d += p
		center_2d /= poly.size()
		
		var dir_2d = (center_2d - impact).normalized()
		var local_force = Vector3(dir_2d.x, dir_2d.y, 0) * explosion_force
		local_force += Vector3(0, 0, rng.randf_range(-1, 3)) 
		
		var global_force = global_transform.basis * local_force
		rb.call_deferred("apply_impulse", global_force)
		
		if auto_despawn:
			get_tree().create_timer(despawn_time).timeout.connect(rb.queue_free)

# --- 6. HELPERS ---

func _get_polygon_bounding_rect(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty(): return Rect2()
	var min_v = pts[0]; var max_v = pts[0]
	for p in pts:
		min_v.x = min(min_v.x, p.x); min_v.y = min(min_v.y, p.y)
		max_v.x = max(max_v.x, p.x); max_v.y = max(max_v.y, p.y)
	return Rect2(min_v, max_v - min_v)

func _intersect_ray_plane(ray_origin: Vector2, ray_dir: Vector2, plane_point: Vector2, plane_normal: Vector2) -> Vector2:
	var denom = plane_normal.dot(ray_dir)
	if abs(denom) < 0.0001: return ray_origin
	var t = plane_normal.dot(plane_point - ray_origin) / denom
	return ray_origin + ray_dir * t

func _poly_to_mesh(poly: PackedVector2Array, extrude_depth: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var indices = Geometry2D.triangulate_polygon(poly)
	if indices.is_empty(): return null
	
	var offset = Vector3(0, 0, -extrude_depth)
	var n_f = Vector3(0,0,1); var n_b = Vector3(0,0,-1)
	
	var uv_scale = 0.5; var uv_offset = Vector2(0.5, 0.5)
	var get_uv = func(vec3): return Vector2(vec3.x, -vec3.y) * uv_scale + uv_offset
	
	for i in range(0, indices.size(), 3):
		var p1 = poly[indices[i]]; var p2 = poly[indices[i+1]]; var p3 = poly[indices[i+2]]
		var v1 = Vector3(p1.x, p1.y, 0); var v2 = Vector3(p2.x, p2.y, 0); var v3 = Vector3(p3.x, p3.y, 0)
		
		st.set_normal(n_f)
		st.set_uv(get_uv.call(v3)); st.add_vertex(v3)
		st.set_uv(get_uv.call(v2)); st.add_vertex(v2)
		st.set_uv(get_uv.call(v1)); st.add_vertex(v1)
		
		st.set_normal(n_b)
		st.set_uv(get_uv.call(v1)); st.add_vertex(v1 + offset)
		st.set_uv(get_uv.call(v2)); st.add_vertex(v2 + offset)
		st.set_uv(get_uv.call(v3)); st.add_vertex(v3 + offset)

	for i in range(poly.size()):
		var p1 = Vector3(poly[i].x, poly[i].y, 0)
		var p2 = Vector3(poly[(i+1)%poly.size()].x, poly[(i+1)%poly.size()].y, 0)
		var sn = (p2-p1).cross(Vector3(0,0,1)).normalized()
		
		st.set_normal(sn)
		st.set_uv(get_uv.call(p1)); st.add_vertex(p1)
		st.set_uv(get_uv.call(p2)); st.add_vertex(p2)
		st.set_uv(get_uv.call(p1)); st.add_vertex(p1 + offset)
		
		st.set_uv(get_uv.call(p2)); st.add_vertex(p2)
		st.set_uv(get_uv.call(p2)); st.add_vertex(p2 + offset)
		st.set_uv(get_uv.call(p1)); st.add_vertex(p1 + offset)
	
	return st.commit()

func _get_default_glass_material() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.1, 0.3, 0.4, 0.3)
	m.roughness = 0.1
	m.metallic = 0.5
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # Glass is double-sided
	return m
