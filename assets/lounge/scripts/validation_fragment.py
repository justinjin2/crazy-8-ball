# Independent final validation helpers for LoungeBuilder.py.
# Requires the builder globals bpy, bmesh, math, Vector, json, Path, OUTPUT_DIR.
# This file contains no top-level Blender mutation and does not call any operator.

_VALIDATION_GROUPS = ('Architecture', 'Furniture', 'Props', 'Signs', 'Emissive', 'Collision')
_VALIDATION_EPS = 1e-5
_UV_BOUNDS_EPS = 1e-7
_UV_INTERIOR_AREA_EPS = 1e-12


def _validation_objects(objects=None):
    source = bpy.context.scene.objects if objects is None else objects
    return sorted((o for o in source if o.type == 'MESH' and
                   o.get('export_group') in _VALIDATION_GROUPS), key=lambda o: o.name)


def _validation_check(name, passed, detail=None):
    result = {'name': name, 'passed': bool(passed)}
    if detail is not None:
        result['detail'] = detail
    return result


def _uv_cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _uv_polygon_area(poly):
    if len(poly) < 3:
        return 0.0
    # Translation before summation reduces cancellation for very small UV islands.
    x0, y0 = poly[0]
    return abs(sum((poly[i][0] - x0) * (poly[i + 1][1] - y0) -
                   (poly[i][1] - y0) * (poly[i + 1][0] - x0)
                   for i in range(1, len(poly) - 1))) * 0.5


def _uv_triangle_intersection_area(triangle_a, triangle_b):
    """Exact convex clipping in double precision; shared boundaries have zero area."""
    clip = list(triangle_b)
    if _uv_cross(clip[0], clip[1], clip[2]) < 0:
        clip.reverse()
    polygon = list(triangle_a)
    for edge_i in range(3):
        a, b = clip[edge_i], clip[(edge_i + 1) % 3]
        source, polygon = polygon, []
        if not source:
            break
        previous = source[-1]
        previous_distance = _uv_cross(a, b, previous)
        for current in source:
            current_distance = _uv_cross(a, b, current)
            current_inside = current_distance >= 0.0
            previous_inside = previous_distance >= 0.0
            if current_inside != previous_inside:
                divisor = previous_distance - current_distance
                if divisor != 0.0:
                    fraction = previous_distance / divisor
                    polygon.append((previous[0] + fraction * (current[0] - previous[0]),
                                    previous[1] + fraction * (current[1] - previous[1])))
            if current_inside:
                polygon.append(current)
            previous, previous_distance = current, current_distance
    return _uv_polygon_area(polygon)


def _validate_uv_triangles(triangles):
    """Bin all triangles and test every candidate; no sampling or early pass shortcut."""
    triangle_count = len(triangles)
    grid = max(8, min(128, int(math.ceil(math.sqrt(max(1, triangle_count))))))
    bins = {}
    overlaps = []
    overlap_count = 0
    max_overlap_area = 0.0
    candidate_count = 0
    degenerate_indices = []
    boxes = []
    for tri_index, tri in enumerate(triangles):
        if abs(_uv_cross(tri[0], tri[1], tri[2])) * 0.5 <= 1e-16:
            degenerate_indices.append(tri_index)
        xs, ys = [p[0] for p in tri], [p[1] for p in tri]
        box = (min(xs), max(xs), min(ys), max(ys))
        boxes.append(box)
        # Bounds are separately validated. Clamp invalid UVs to avoid huge bin allocation.
        x0 = max(-1, min(grid, int(math.floor(box[0] * grid))))
        x1 = max(-1, min(grid, int(math.floor(box[1] * grid))))
        y0 = max(-1, min(grid, int(math.floor(box[2] * grid))))
        y1 = max(-1, min(grid, int(math.floor(box[3] * grid))))
        keys = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
        candidates = set()
        for key in keys:
            candidates.update(bins.get(key, ()))
        for other_index in candidates:
            other_box = boxes[other_index]
            if (min(box[1], other_box[1]) <= max(box[0], other_box[0]) or
                    min(box[3], other_box[3]) <= max(box[2], other_box[2])):
                continue
            candidate_count += 1
            area = _uv_triangle_intersection_area(tri, triangles[other_index])
            if area > _UV_INTERIOR_AREA_EPS:
                overlap_count += 1
                max_overlap_area = max(max_overlap_area, area)
                if len(overlaps) < 30:
                    overlaps.append({'triangles': [other_index, tri_index], 'area': area})
        for key in keys:
            bins.setdefault(key, []).append(tri_index)
    return {'passed': overlap_count == 0 and not degenerate_indices,
            'triangle_count': triangle_count, 'candidate_pairs_tested': candidate_count,
            'interior_overlap_pair_count': overlap_count,
            'maximum_interior_overlap_area': max_overlap_area,
            'overlap_examples': overlaps,
            'degenerate_uv_triangle_count': len(degenerate_indices),
            'degenerate_uv_triangle_examples': degenerate_indices[:30],
            'interior_area_tolerance': _UV_INTERIOR_AREA_EPS,
            'method': 'Exhaustive spatial-bin candidate search and convex triangle clipping.'}


def _validation_world_bounds(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return [min(p[0] for p in corners), max(p[0] for p in corners),
            min(p[1] for p in corners), max(p[1] for p in corners),
            min(p[2] for p in corners), max(p[2] for p in corners)]


def _validation_png_dimensions(path):
    import struct
    with open(path, 'rb') as file:
        header = file.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Not a PNG file')
    return list(struct.unpack('>II', header[16:24]))


def validate_meshes(objects=None):
    """Read-only, exhaustive validation of every tagged environment export mesh."""
    mesh_objects = _validation_objects(objects)
    results = []
    checks = []
    set_names = set()
    for obj in mesh_objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        checks_local = []
        checks_local.append(_validation_check('triangle_limit', triangles <= 10000, triangles))
        checks_local.append(_validation_check('triangulated', all(len(p.vertices) == 3 for p in mesh.polygons),
                                              {'non_triangular_polygons': sum(len(p.vertices) != 3 for p in mesh.polygons)}))
        checks_local.append(_validation_check('nonempty_geometry', len(mesh.vertices) > 0 and triangles > 0))
        material_ok = (len(mesh.materials) == 1 and mesh.materials[0] is not None and
                       all(p.material_index == 0 for p in mesh.polygons))
        checks_local.append(_validation_check('exactly_one_material', material_ok, len(mesh.materials)))
        checks_local.append(_validation_check('no_live_modifiers', len(obj.modifiers) == 0, len(obj.modifiers)))
        checks_local.append(_validation_check('exactly_one_uv_map', len(mesh.uv_layers) == 1, len(mesh.uv_layers)))
        finite_geometry = all(math.isfinite(float(v.co[k])) for v in mesh.vertices for k in range(3))
        checks_local.append(_validation_check('finite_vertex_coordinates', finite_geometry))
        uv_detail = None
        if len(mesh.uv_layers) == 1:
            uv_layer = mesh.uv_layers[0].data
            coordinates = [(float(v.uv.x), float(v.uv.y)) for v in uv_layer]
            finite_uv = all(math.isfinite(p[0]) and math.isfinite(p[1]) for p in coordinates)
            bounds_ok = finite_uv and all(-_UV_BOUNDS_EPS <= n <= 1.0 + _UV_BOUNDS_EPS
                                          for p in coordinates for n in p)
            checks_local.append(_validation_check('uv_bounds_0_1', bounds_ok,
                {'bounds': ([min(p[0] for p in coordinates), max(p[0] for p in coordinates),
                             min(p[1] for p in coordinates), max(p[1] for p in coordinates)]
                            if coordinates and finite_uv else None), 'tolerance': _UV_BOUNDS_EPS}))
            if finite_uv:
                uv_triangles = [tuple(coordinates[index] for index in triangle.loops)
                                for triangle in mesh.loop_triangles]
                uv_detail = _validate_uv_triangles(uv_triangles)
                checks_local.append(_validation_check('uv_no_interior_overlap',
                    uv_detail['interior_overlap_pair_count'] == 0, uv_detail))
                checks_local.append(_validation_check('uv_no_degenerate_triangles',
                    uv_detail['degenerate_uv_triangle_count'] == 0,
                    uv_detail['degenerate_uv_triangle_count']))
            else:
                checks_local.append(_validation_check('uv_no_interior_overlap', False, 'Non-finite UV coordinates.'))
        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            nonmanifold_edges = sum(not e.is_manifold for e in bm.edges)
            boundary_edges = sum(e.is_boundary for e in bm.edges)
            wire_edges = sum(e.is_wire for e in bm.edges)
            nonmanifold_vertices = sum(not v.is_manifold for v in bm.verts)
            zero_area_faces = sum(face.calc_area() <= 1e-12 for face in bm.faces)
            opening_reason = str(obj.get('intentional_open_reason', '')).strip()
            closed = nonmanifold_edges == 0 and nonmanifold_vertices == 0
            # A documented open surface may have boundary edges, but neither wire edges
            # nor edges with >2 incident faces are legitimized by that exception.
            invalid_branch_edges = sum(len(e.link_faces) > 2 for e in bm.edges)
            intentional_open = (bool(opening_reason) and boundary_edges > 0 and wire_edges == 0 and
                                invalid_branch_edges == 0)
            manifold_detail = {'closed_manifold': closed, 'nonmanifold_edges': nonmanifold_edges,
                              'boundary_edges': boundary_edges, 'wire_edges': wire_edges,
                              'nonmanifold_vertices': nonmanifold_vertices,
                              'intentional_open_reason': opening_reason or None}
            checks_local.append(_validation_check('manifold_or_documented_open', closed or intentional_open,
                                                  manifold_detail))
            checks_local.append(_validation_check('no_zero_area_faces', zero_area_faces == 0, zero_area_faces))
        finally:
            bm.free()
        translation, rotation, scale = obj.matrix_world.decompose()
        rotation_matrix = rotation.to_matrix()
        rotation_error = max(abs(float(rotation_matrix[i][j]) - (1.0 if i == j else 0.0))
                             for i in range(3) for j in range(3))
        scale_error = max(abs(float(scale[k]) - 1.0) for k in range(3))
        transform_ok = rotation_error <= _VALIDATION_EPS and scale_error <= _VALIDATION_EPS
        checks_local.append(_validation_check('rotation_scale_applied', transform_ok,
            {'rotation_matrix_error': rotation_error, 'unit_scale_error': scale_error,
             'tolerance': _VALIDATION_EPS}))
        origin_policy = obj.get('origin_policy', '')
        if origin_policy == 'world':
            origin_error = max(abs(float(translation[k])) for k in range(3))
            origin_ok = origin_error <= _VALIDATION_EPS
            origin_detail = {'policy': 'world', 'world_origin_error': origin_error}
        elif origin_policy == 'base_center' and mesh.vertices:
            local_min = [min(float(v.co[k]) for v in mesh.vertices) for k in range(3)]
            local_max = [max(float(v.co[k]) for v in mesh.vertices) for k in range(3)]
            center_base = [(local_min[0] + local_max[0]) * 0.5,
                           (local_min[1] + local_max[1]) * 0.5, local_min[2]]
            origin_error = max(abs(v) for v in center_base)
            origin_ok = origin_error <= _VALIDATION_EPS
            origin_detail = {'policy': 'base_center', 'local_base_center': center_base,
                            'world_location': list(translation), 'origin_error': origin_error}
        else:
            origin_ok = False
            origin_detail = {'policy': origin_policy, 'error': 'Missing/unknown origin_policy or empty mesh.'}
        checks_local.append(_validation_check('sensible_origin', origin_ok, origin_detail))
        group = obj.get('export_group')
        if group == 'Collision':
            checks_local.append(_validation_check('collision_under_200_triangles', triangles < 200, triangles))
            checks_local.append(_validation_check('collision_name', obj.name.startswith('COL_')))
        if group == 'Emissive':
            checks_local.append(_validation_check('emissive_name', obj.name.startswith('Emissive_')))
        set_name = str(obj.get('set_name', '')).strip()
        if set_name:
            set_names.add(set_name)
        results.append({'object': obj.name, 'group': group, 'triangles': triangles,
                        'vertices': len(mesh.vertices), 'set_name': set_name or None,
                        'origin_policy': origin_policy, 'passed': all(c['passed'] for c in checks_local),
                        'checks': checks_local})
    triangle_total = sum(r['triangles'] for r in results)
    checks.append(_validation_check('environment_triangle_limit', triangle_total <= 150000,
                                    {'total': triangle_total, 'limit': 150000, 'includes_collision': True}))
    checks.append(_validation_check('environment_meshes_present', bool(mesh_objects)))
    checks.append(_validation_check('all_six_export_groups_present',
        all(any(r['group'] == group for r in results) for group in _VALIDATION_GROUPS)))
    checks.append(_validation_check('texture_set_limit', len(set_names) <= 12, sorted(set_names)))
    texture_results = []
    for set_name in sorted(set_names):
        map_results = []
        for suffix in ('Color', 'Roughness', 'Normal', 'Metalness'):
            path = OUTPUT_DIR / 'textures' / (set_name + '_' + suffix + '.png')
            required = suffix in ('Color', 'Roughness')
            if path.exists():
                try:
                    dimensions = _validation_png_dimensions(path)
                    valid = all(0 < d <= 1024 for d in dimensions)
                    map_results.append({'map': suffix, 'passed': valid, 'dimensions': dimensions})
                except Exception as error:
                    map_results.append({'map': suffix, 'passed': False, 'error': str(error)})
            elif required:
                map_results.append({'map': suffix, 'passed': False, 'error': 'Required PNG is missing.'})
        texture_results.append({'set': set_name, 'passed': all(m['passed'] for m in map_results),
                                'maps': map_results})
    checks.append(_validation_check('texture_maps_present_and_dimensions',
                                    all(t['passed'] for t in texture_results), texture_results))
    names = {o.name for o in mesh_objects}
    checks.append(_validation_check('glass_windows_exists', 'Glass_Windows' in names))
    checks.append(_validation_check('emissive_meshes_exist', any(n.startswith('Emissive_') for n in names)))
    checks.append(_validation_check('collision_meshes_exist', any(n.startswith('COL_') for n in names)))
    return {'passed': all(r['passed'] for r in results) and all(c['passed'] for c in checks),
            'mesh_count': len(results), 'triangle_total': triangle_total, 'texture_sets': sorted(set_names),
            'objects': results, 'checks': checks,
            'transform_convention': 'Applied world rotation and unit scale. World-origin architecture has zero translation; movable base-center origins intentionally retain their placement translation.',
            'intentional_open_property': 'intentional_open_reason',
            'tables_excluded': True}


def _validation_plan_distance(a, b):
    dx = max(a[0] - b[1], b[0] - a[1], 0.0)
    dy = max(a[2] - b[3], b[2] - a[3], 0.0)
    return math.hypot(dx, dy)


def validate_clearance(objects=None, clearance=10.0):
    """Check actual table transforms and tagged obstruction bounds against every table."""
    scene_objects = list(bpy.context.scene.objects if objects is None else objects)
    by_name = {o.name: o for o in scene_objects}
    obstacles = sorted((o for o in scene_objects if o.type == 'MESH' and o.get('clearance_obstacle', False)),
                       key=lambda o: o.name)
    obstacle_bounds = [(o.name, _validation_world_bounds(o)) for o in obstacles]
    table_data = []
    checks = []
    missing = []
    for table_i in range(1, 13):
        name = 'Table_%02d' % table_i
        obj = by_name.get(name)
        if obj is None:
            missing.append(name)
            continue
        corners = [obj.matrix_world @ Vector((x, y, 0))
                   for x in (-8.88, 8.88) for y in (-4.88, 4.88)]
        bounds = [min(p.x for p in corners), max(p.x for p in corners),
                  min(p.y for p in corners), max(p.y for p in corners)]
        center = obj.matrix_world.translation
        table_data.append({'name': name, 'center_blender': list(center),
                           'center_roblox': [float(center.x), float(center.z), float(-center.y)],
                           'plan_bounds': bounds, 'object': obj})
    all_instance_names = [o.name for o in scene_objects if o.name.startswith('Table_') and
                          len(o.name) >= 8 and o.name[6:8].isdigit() and o.type == 'EMPTY' and
                          getattr(o, 'instance_type', None) == 'COLLECTION']
    checks.append(_validation_check('exactly_twelve_table_instances',
        not missing and len(table_data) == 12 and len(all_instance_names) == 12,
        {'found': len(table_data), 'collection_instance_count': len(all_instance_names), 'missing': missing}))
    table_pairs = []
    obstacle_failures = []
    per_table = []
    for table_index, table in enumerate(table_data):
        bounds = table['plan_bounds']
        distances = []
        sides = {'left': None, 'right': None, 'front': None, 'back': None}
        obstruction_list = [(other['name'], other['plan_bounds']) for other in table_data if other is not table]
        obstruction_list.extend(obstacle_bounds)
        for obstacle_name, other_bounds in obstruction_list:
            distance = _validation_plan_distance(bounds, other_bounds)
            distances.append((distance, obstacle_name))
            if distance < clearance - 1e-8:
                obstacle_failures.append({'table': table['name'], 'obstacle': obstacle_name,
                                          'distance': distance, 'required': clearance})
            overlap_x = min(bounds[1], other_bounds[1]) >= max(bounds[0], other_bounds[0])
            overlap_y = min(bounds[3], other_bounds[3]) >= max(bounds[2], other_bounds[2])
            candidates = {}
            if overlap_y and other_bounds[1] <= bounds[0]:
                candidates['left'] = bounds[0] - other_bounds[1]
            if overlap_y and other_bounds[0] >= bounds[1]:
                candidates['right'] = other_bounds[0] - bounds[1]
            if overlap_x and other_bounds[3] <= bounds[2]:
                candidates['front'] = bounds[2] - other_bounds[3]
            if overlap_x and other_bounds[2] >= bounds[3]:
                candidates['back'] = other_bounds[2] - bounds[3]
            for side, distance_on_side in candidates.items():
                if sides[side] is None or distance_on_side < sides[side]['distance']:
                    sides[side] = {'distance': distance_on_side, 'obstacle': obstacle_name}
        distances.sort()
        per_table.append({'table': table['name'], 'center_blender': table['center_blender'],
                          'center_roblox': table['center_roblox'], 'plan_bounds': bounds,
                          'minimum_clearance': distances[0][0] if distances else None,
                          'nearest_obstacle': distances[0][1] if distances else None,
                          'directional_clearances': sides,
                          'passed': bool(distances) and distances[0][0] >= clearance - 1e-8})
        for other in table_data[table_index + 1:]:
            distance = _validation_plan_distance(bounds, other['plan_bounds'])
            table_pairs.append({'tables': [table['name'], other['name']], 'distance': distance,
                                'passed': distance >= clearance - 1e-8})
    rows_valid = len(table_data) == 12
    if rows_valid:
        rows = [table_data[i:i + 4] for i in (0, 4, 8)]
        rows_valid = all(max(t['center_blender'][1] for t in row) - min(t['center_blender'][1] for t in row) < _VALIDATION_EPS
                         and max(t['center_blender'][2] for t in row) - min(t['center_blender'][2] for t in row) < _VALIDATION_EPS
                         and all(row[i]['center_blender'][0] < row[i + 1]['center_blender'][0] for i in range(3))
                         for row in rows)
        rows_valid = rows_valid and all(rows[i][0]['center_blender'][1] < rows[i + 1][0]['center_blender'][1] and
                                       rows[i][0]['center_blender'][2] < rows[i + 1][0]['center_blender'][2]
                                       for i in range(2))
        rows_valid = rows_valid and all(abs(rows[0][col]['center_blender'][0] - rows[row][col]['center_blender'][0]) < _VALIDATION_EPS
                                       for row in (1, 2) for col in range(4))
    checks.append(_validation_check('three_ascending_rows_of_four', rows_valid))
    checks.append(_validation_check('tagged_clearance_obstacles_exist', bool(obstacle_bounds), len(obstacle_bounds)))
    checks.append(_validation_check('all_table_clearances', bool(per_table) and all(t['passed'] for t in per_table),
                                    {'required': clearance, 'failure_count': len(obstacle_failures)}))
    return {'passed': all(c['passed'] for c in checks), 'checks': checks, 'tables': per_table,
            'table_pair_distances': table_pairs, 'obstacle_count': len(obstacle_bounds),
            'obstacle_bounds': [{'object': name, 'bounds': bounds} for name, bounds in obstacle_bounds],
            'failures': obstacle_failures, 'minimum_required': clearance,
            'scope': 'Native XY plan separation to every table and mesh tagged clearance_obstacle. Supporting floors, flat rugs, overhead ceiling/pendants and in-footprint table number signage are intentionally excluded by builder tags. Stair and terrace edges are included regardless of elevation.',
            'method': 'World-space authoritative table footprints and actual obstruction AABBs; Euclidean footprint distance plus four facing-side clearances. Only 1e-8 arithmetic slack, not a design clearance allowance.'}


def write_validation(mesh_results=None, clearance_results=None, extra_checks=None, filename='Validation'):
    """Print and save the complete report; caller supplies final export/render/document checks."""
    if mesh_results is None:
        mesh_results = validate_meshes()
    if clearance_results is None:
        clearance_results = validate_clearance()
    if extra_checks is None:
        extra_checks = []
    elif isinstance(extra_checks, dict):
        extra_checks = [_validation_check(name, value.get('passed', False), value)
                        if isinstance(value, dict) else _validation_check(name, value)
                        for name, value in extra_checks.items()]
    report = {'passed': bool(mesh_results['passed'] and clearance_results['passed'] and
                             all(c.get('passed', False) for c in extra_checks)),
              'mesh_validation': mesh_results, 'clearance_validation': clearance_results,
              'additional_checks': extra_checks}
    json_path = OUTPUT_DIR / (filename + '.json')
    markdown_path = OUTPUT_DIR / (filename + '.md')
    json_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    lines = ['# Lounge validation', '', '**Result: %s**' % ('PASS' if report['passed'] else 'FAIL'), '',
             'All exported environment meshes are checked; pool-table source meshes are excluded.', '',
             '| Object | Package | Triangles | Result |', '|---|---|---:|---|']
    for obj in mesh_results.get('objects', []):
        lines.append('| %s | %s | %s | %s |' % (obj['object'], obj['group'], obj['triangles'],
                                                'PASS' if obj['passed'] else 'FAIL'))
    lines.extend(['', 'Environment triangles: **%s / 150,000**.' % mesh_results.get('triangle_total', '?'), '',
                  'Texture sets: %s.' % (', '.join(mesh_results.get('texture_sets', [])) or '(none)'), '',
                  '## Table clearance', '', '| Table | Minimum clearance (studs) | Closest obstruction | Result |',
                  '|---|---:|---|---|'])
    for table in clearance_results.get('tables', []):
        distance = table.get('minimum_clearance')
        lines.append('| %s | %s | %s | %s |' % (table['table'], '%.8f' % distance if distance is not None else 'missing',
                    table.get('nearest_obstacle'), 'PASS' if table['passed'] else 'FAIL'))
    lines.extend(['', clearance_results.get('scope', ''), '', clearance_results.get('method', ''), '',
                  '## Checks', ''])
    all_checks = list(mesh_results.get('checks', [])) + list(clearance_results.get('checks', [])) + list(extra_checks)
    for check in all_checks:
        lines.append('- %s: %s' % ('PASS' if check.get('passed') else 'FAIL', check['name']))
    failures = [(obj['object'], check) for obj in mesh_results.get('objects', [])
                for check in obj.get('checks', []) if not check['passed']]
    if failures:
        lines.extend(['', '## Mesh failures', ''])
        for object_name, check in failures:
            lines.append('- %s — %s: %s' % (object_name, check['name'], json.dumps(check.get('detail', ''))))
    openings = [(obj['object'], check['detail'].get('intentional_open_reason'))
                for obj in mesh_results.get('objects', []) for check in obj['checks']
                if check['name'] == 'manifold_or_documented_open' and check['detail'].get('intentional_open_reason')]
    if openings:
        lines.extend(['', '## Intentionally open geometry', ''])
        lines.extend('- %s: %s' % entry for entry in openings)
    lines.extend(['', mesh_results.get('transform_convention', ''), '',
                  'UVs use exhaustive spatial-bin candidate testing and numeric triangle clipping; '
                  'shared edges have zero area. Bounds tolerance is 1e-7 UV and interior area tolerance is 1e-12 UV². '
                  'Applied transforms and origin checks use 1e-5 stud tolerance. FBX coordinate reimport must be '
                  'supplied separately at the stricter 1e-6 stud tolerance.', '',
                  'Detailed per-object results, pair distances, UV overlap counts, texture dimensions, and checks: `%s`.' % json_path.name, ''])
    markdown_path.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return report
