# Delivery documentation helpers for integration into LoungeBuilder.py.
# Requires bpy, math, json, Path, OUTPUT_DIR, and PARAMETERS from the builder.
# No top-level Blender interactions or mutations.


def _docs_export_position(vector):
    return [round(float(vector[0]), 8), round(float(vector[2]), 8), round(-float(vector[1]), 8)]


def write_markers():
    """Write real scene transforms in exported Roblox studs / Y-up coordinates."""
    scene = bpy.context.scene
    objects = scene.objects
    tables, pendants = [], []
    for index in range(1, 13):
        table_name = 'Table_%02d' % index
        light_name = 'Light_Pendant_%02d' % index
        table = objects.get(table_name)
        pendant = objects.get(light_name)
        if table is None or pendant is None:
            raise RuntimeError('Marker delivery requires both %s and %s.' % (table_name, light_name))
        center = table.matrix_world.translation
        rotation_y = float(table.get('exported_y_rotation_degrees', PARAMETERS.get('table_rotation_degrees', 90.0)))
        tables.append({'name': table_name, 'table_number': index,
                       'row': (index - 1) // 4 + 1, 'column': (index - 1) % 4 + 1,
                       'position': _docs_export_position(center),
                       'rotation_y_degrees': rotation_y,
                       'scale': [1, 1, 1],
                       'source_asset': '../table/PoolTable_9ft.blend',
                       'native_source_footprint_studs': [17.76, 9.76],
                       'placed_plan_footprint_studs': [9.76, 17.76],
                       'cloth_height_above_floor': 2.9})
        pendants.append({'name': light_name, 'table': table_name,
                         'position': _docs_export_position(pendant.matrix_world.translation),
                         'fixture_bottom_y': round(float(center.z) + float(PARAMETERS.get('pendant_bottom', 7.5)), 8),
                         'color_temperature_K': int(pendant.get('temperature_K', 3000)),
                         'suggested_roblox_light': {'ClassName': 'SurfaceLight', 'Face': 'Bottom',
                             'Brightness': 1.8, 'Range': 24, 'Angle': 120, 'Shadows': False,
                             'Color': [255, 177, 110]}})
    marker_data = {
        'schema_version': 1,
        'units': 'studs',
        'coordinate_system': 'Roblox Y-up; Blender (x,y,z) maps to (x,z,-y)',
        'position_format': ['X', 'Y', 'Z'],
        'rotation_format': 'degrees around Roblox +Y; yaw 0 faces Roblox -Z',
        'rgb_format': '0..255 sRGB arrays; use Color3.fromRGB',
        'assembly_origin': [0, 0, 0],
        'tables': tables,
        'pendants': pendants,
        'spawn': {'name': 'Spawn_Lounge', 'position': [0.0, 0.1, 20.0],
                  'rotation_y_degrees': 0.0, 'facing_direction': [0, 0, -1],
                  'purpose': 'Floor marker in the seating area. Set SpawnLocation or character height above this floor marker as appropriate.'},
        'suggested_roblox_lighting': {
            'ClockTime': 17.4, 'Brightness': 2.0,
            'Ambient': [150, 146, 133], 'OutdoorAmbient': [170, 154, 130],
            'ColorShift_Top': [18, 10, 3],
            'EnvironmentDiffuseScale': 0.65, 'EnvironmentSpecularScale': 0.5,
            'Bloom': {'Enabled': True, 'Intensity': 0.12, 'Size': 20, 'Threshold': 1.2},
            'ColorCorrection': {'Enabled': True, 'Brightness': 0.02, 'Contrast': 0.04,
                                'Saturation': 0.04, 'TintColor': [255, 244, 224]}},
        'notes': [
            'Tables are linked scene placeholders and are excluded from every lounge FBX.',
            'Pendant positions are light emission positions from the actual Blender scene; fixture_bottom_y records the separate 7.5-stud mounting rule.',
            'SurfaceLight values are a starting point for Studio; place each light on a downward-facing invisible mount or the matching Emissive_Pendant mesh.',
            'Neon is a flat material assignment and does not replace the corresponding Roblox light.',
            'Suggested Roblox lighting was not uploaded to or evaluated inside Studio.'
        ]
    }
    path = OUTPUT_DIR / 'Markers.json'
    path.write_text(json.dumps(marker_data, indent=2), encoding='utf-8')
    return marker_data


def _docs_status(checks):
    checks = list(checks)
    return 'PENDING' if not checks else ('PASS' if all(c.get('passed', False) for c in checks) else 'FAIL')


def _docs_dimensions(path):
    import struct
    try:
        with open(path, 'rb') as file:
            header = file.read(24)
        if len(header) == 24 and header[:8] == b'\x89PNG\r\n\x1a\n':
            return '%s × %s' % struct.unpack('>II', header[16:24])
    except (OSError, ValueError):
        pass
    return 'unreadable'


def write_readme(report=None):
    """Generate Readme.md from the current delivery, without inventing validation success."""
    mesh_report = report.get('mesh_validation', {}) if report is not None else {}
    clearance_report = report.get('clearance_validation', {}) if report is not None else {}
    objects = mesh_report.get('objects', [])
    global_checks = list(mesh_report.get('checks', [])) + list(clearance_report.get('checks', []))
    additional_checks = list(report.get('additional_checks', [])) if report is not None else []
    all_checks = global_checks + additional_checks
    mesh_checks = [check for obj in objects for check in obj.get('checks', [])]
    status = 'PENDING' if report is None else ('PASS' if report.get('passed', False) else 'FAIL')
    groups = ('Architecture', 'Furniture', 'Props', 'Signs', 'Emissive', 'Collision')
    texture_dir = OUTPUT_DIR / 'textures'
    actual_sets = sorted(path.name[:-10] for path in texture_dir.glob('*_Color.png'))
    total = mesh_report.get('triangle_total')
    maximum = max((obj['triangles'] for obj in objects), default=None)
    dimensions = PARAMETERS.get('hero_resolution', [1920, 1080])
    samples = PARAMETERS.get('hero_samples', 128)
    lines = [
        '# 8BALL Lounge — delivery notes', '',
        'Built through the connected Blender MCP in Blender 5.2.2 LTS. The lounge uses cream plaster, '
        'honey timber, teal seating, blue playing-zone rugs, coral and butter accents, and warm sunset lighting. '
        'Twelve unchanged source-table collection instances form three ascending rows of four. '
        'There is no real-world table branding.', '',
        '**Final validation: %s.** %s' % (status,
            'Read `Validation.md` for the readable results and `Validation.json` for complete numeric checks.'
            if report is not None else
            'This documentation checkpoint precedes the final validation gate; no validation success is claimed.'), '',
        'Open `Lounge.blend`. The embedded `LoungeBuilder.py` and the standalone script are the rebuildable source. '
        '`PARAMETERS` controls room dimensions, table positions, stair dimensions, palette-related construction, '
        'texture size, AO strength, camera, and render settings. All new output remains beside the script. '
        '`../table/PoolTable.py` and the source table files remain unchanged.', '',
        '## Coordinates and layout', '',
        'One Blender coordinate unit is one Roblox stud, with 0.16 stud per inch. Authoring is native Z-up. '
        'FBX exports use −Z Forward / Y Up, scale factor 1, and FBX Unit Scale, transforming '
        '`(x, y, z)` into `(x, z, −y)`. All six packages retain the same world-zero assembly origin. '
        'Architecture uses world-zero mesh origins. Movable furniture keeps base-centre pivots with placement '
        'translation retained; rotations and scales are applied. Table instances rotate +90° around native Z, '
        'equivalent to +90° around exported Roblox Y.', '',
        '| Parameter | Value |', '|---|---|',
        '| Interior dimensions | %.2f × %.2f studs |' % (
            2 * PARAMETERS.get('room_half_width', 49),
            PARAMETERS.get('room_back', 106) - PARAMETERS.get('room_front', -35)),
        '| Table column centres, native X | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('column_x', [-30,-10,10,30])),
        '| Table row centres, native Y | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('row_y', [0,43,86])),
        '| Floor heights, native Z / exported Y | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('tier_z', [0,2.4,4.8])),
        '| Rotated table footprint | 9.76 across X × 17.76 along native Y |',
        '| Source table cloth / rail top | 2.9 / 3.2328 studs above each floor |',
        '| Minimum table clearance | 10 studs to tables, walls, furniture, railings, and steps |',
        '| Each stair flight | Three 0.8-rise × 1.6-run steps; %g-stud usable width |' % PARAMETERS.get('stair_width', 80),
        '| Pendant lower edge | 7.5 studs above its table floor |',
        '| Foreground entrance | 5 wide × 8 high |', '',
        'Shared ten-stud corridors separate adjacent tables. The long room and generous tier spacing prioritize '
        'the numeric cue clearance over the tightly packed reference image. Table numbers 1–4 are the front row, '
        '5–8 the middle row, and 9–12 the rear row. `DECISIONS.md` records architectural and composition tradeoffs.', '',
        '## Package assembly in Roblox Studio', '',
        '1. Import each of the six FBX files below. In File Geometry, set **Scale Unit: Stud** and keep scale factor **1**. '
        'Retain child MeshPart positions and pivots. Place the package containers at the common assembly origin; '
        'do not individually centre, resize, or reposition their children.',
        '2. Import the existing table package separately once using the same Stud setting. Duplicate or instance that '
        'model twelve times using `Markers.json` positions and Y rotations. The lounge FBX files intentionally contain '
        'no table meshes. The Blender file references one appended collection of the source’s seven finished table meshes.',
        '3. Assign one SurfaceAppearance per textured MeshPart. Use its `set_name` / baked material name to choose '
        '`<Set>_Color.png` for ColorMap and `<Set>_Roughness.png` for RoughnessMap. Assign MetalnessMap when the set '
        'has a matching metalness file. Texture colour spaces are sRGB for Color and data/Non-Color for Roughness and Metalness.',
        '4. Assign `Emissive_*` meshes Roblox **Neon**, using their flat warm colours. They require no SurfaceAppearance. '
        'Assign `Glass_Windows` Roblox **Glass** with a light blue tint and approximately 0.65 transparency. '
        'Keep glass separate from opaque architecture.',
        '5. Keep every environment object anchored. Use Box collision for simple rectangular architecture and Hull for '
        'appropriate convex pieces. Import `COL_*` proxies from the Collision package, set Transparency=1 and '
        'CanCollide=true, and use Box/Hull collision as appropriate. Stair and tier-edge proxies are intentionally simple. '
        'Set decorative furniture details, plants, art, signs, Neon, and glass CanCollide=false; use the supplied proxy '
        'where a decorative assembly needs collision. Disable decorative CastShadow where useful for mobile performance.',
        '6. Add the twelve downward-facing pendant lights and a seating-area spawn using `Markers.json`. '
        'Its positions are already Roblox Y-up studs; do not apply a second axis conversion. '
        'The included Lighting, Bloom, and ColorCorrection values are adjustable starting settings.', '',
        '| File | Contents |', '|---|---|',
        '| `exports/Lounge_Architecture.fbx` | Shell, floors, tiers, steps, ceiling grid, pillars, windows, and separate Glass_Windows |',
        '| `exports/Lounge_Furniture.fbx` | Seating, rugs, coffee table, ottoman, and snack-counter furniture |',
        '| `exports/Lounge_Props.fbx` | Plants, art, clock, cue racks, pendant housings, and small related props |',
        '| `exports/Lounge_Signs.fbx` | Table numbers, separate 1v1 / 2v2 / 3v3 zone signs, Refresh & Play, and blank logo panel |',
        '| `exports/Lounge_Emissive.fbx` | Separate untextured Neon geometry |',
        '| `exports/Lounge_Collision.fbx` | Hidden simple COL_* collision proxies |', '',
        '## Geometry and texture delivery', '',
        'Each exported mesh has one material and one 0–1 UV map. The bake workflow packs related source pieces '
        'into shared atlases by texture set, applies modifiers and transforms as appropriate to the pivot policy, '
        'and triangulates export geometry. `SOURCE_Lounge_*` procedural materials remain available in the blend. '
        'Source BaseColor, Roughness, and Metalness channels use Cycles emission-pass baking; direct lighting and '
        'cast shadows are excluded from Color maps. A separate %g-sample Cycles AO bake is multiplied into BaseColor '
        'at %g%% strength. Maps are %g × %g or smaller. Normal maps are omitted because the restrained stylized '
        'surfaces and modeled bevels do not require them.' % (
            PARAMETERS.get('ao_samples', 32), PARAMETERS.get('ao_blend', .16) * 100,
            PARAMETERS.get('texture_size', 1024), PARAMETERS.get('texture_size', 1024)), '',
        'The `Signs` atlas is separate and replaceable. Zone signs and table placeholders remain independently named '
        'and editable. Replace the sign artwork within its UV island, or update the text in the builder and rebake '
        'the Signs set. `Sign_Logo_Blank` is a blank 10 × 3 stud panel for the game’s own artwork.', '',
        '| Texture set found on disk | Maps | Color dimensions |', '|---|---|---|'
    ]
    for set_name in actual_sets:
        maps = [suffix for suffix in ('Color', 'Roughness', 'Normal', 'Metalness')
                if (texture_dir / (set_name + '_' + suffix + '.png')).exists()]
        lines.append('| %s | %s | %s |' % (set_name, ', '.join(maps),
            _docs_dimensions(texture_dir / (set_name + '_Color.png'))))
    if not actual_sets:
        lines.append('| Pending baking | No Color maps present at this checkpoint | — |')
    lines.extend(['', 'Final per-object triangle counts (table instances excluded):', '',
                  '| Object | FBX group | Texture set | Triangles | Validation |',
                  '|---|---|---|---:|---|'])
    for obj in objects:
        lines.append('| %s | %s | %s | %s | %s |' % (obj['object'].replace('|', '\\|'),
            obj['group'], obj.get('set_name') or 'Untextured', obj['triangles'],
            'PASS' if obj.get('passed') else 'FAIL'))
    if not objects:
        lines.append('| Pending final validation | — | — | — | PENDING |')
    lines.extend(['', 'Environment total: **%s / 150,000 triangles**. Largest exported mesh: **%s / 10,000 triangles**. '
                  'Collision proxies must each remain below 200 triangles. The source table is 19,220 triangles; '
                  'its twelve render instances total 230,640 source-table triangles and are excluded from the lounge '
                  'environment budget and exports.' % (total if total is not None else 'pending',
                                                     maximum if maximum is not None else 'pending'), '',
                  '## Validation', '', '| Check | Result |', '|---|---|'])
    check_categories = [
        ('Per-mesh triangle limit', [c for c in mesh_checks if c['name'] == 'triangle_limit']),
        ('Environment triangle limit', [c for c in global_checks if c['name'] == 'environment_triangle_limit']),
        ('One material / one UV map', [c for c in mesh_checks if c['name'] in ('exactly_one_material','exactly_one_uv_map')]),
        ('UV bounds / no interior overlap', [c for c in mesh_checks if c['name'] in ('uv_bounds_0_1','uv_no_interior_overlap','uv_no_degenerate_triangles')]),
        ('Triangulation / no live modifiers', [c for c in mesh_checks if c['name'] in ('triangulated','no_live_modifiers')]),
        ('Applied rotation/scale and sensible origins', [c for c in mesh_checks if c['name'] in ('rotation_scale_applied','sensible_origin')]),
        ('Manifold or explicitly documented open surfaces', [c for c in mesh_checks if c['name'] == 'manifold_or_documented_open']),
        ('Texture-set count and dimensions', [c for c in global_checks if c['name'] in ('texture_set_limit','texture_maps_present_and_dimensions')]),
        ('Twelve tables / three ascending rows', [c for c in global_checks if c['name'] in ('exactly_twelve_table_instances','three_ascending_rows_of_four')]),
        ('Ten-stud table clearance', [c for c in global_checks if c['name'] == 'all_table_clearances']),
        ('Glass / Neon / collision meshes present', [c for c in global_checks if c['name'] in ('glass_windows_exists','emissive_meshes_exist','collision_meshes_exist')]),
    ]
    for name, checks in check_categories:
        lines.append('| %s | %s |' % (name, _docs_status(checks)))
    for check in additional_checks:
        lines.append('| %s | %s |' % (str(check['name']).replace('|', '\\|'),
                                    'PASS' if check.get('passed') else 'FAIL'))
    lines.extend(['', 'UV validation exhaustively bins candidate triangle pairs and numerically clips their UV triangles '
                  'to test interior intersection; it does not infer validity from an unwrap operator succeeding. '
                  'UV bounds tolerance is 1e-7 and interior-area tolerance is 1e-12 UV². Applied transform and origin '
                  'checks use 1e-5 stud tolerance. The independent FBX reimport coordinate gate uses the stricter '
                  '**1e-6 stud** tolerance in a clean collection.', '',
                  'Clearance validation uses each table’s actual instance transform and authoritative footprint, then '
                  'checks every other table and every tagged wall, furniture, plant, stair, and guardrail bounding box. '
                  'It reports the minimum and four facing-side clearances per table. Supporting floors, flat rugs, '
                  'overhead ceiling/pendants, and overhead table number plaques do not obstruct the floor clearance.', ''])
    openings = [(obj['object'], c.get('detail', {}).get('intentional_open_reason'))
                for obj in objects for c in obj.get('checks', [])
                if c['name'] == 'manifold_or_documented_open' and isinstance(c.get('detail'), dict)
                and c['detail'].get('intentional_open_reason')]
    if openings:
        lines.append('Intentionally open surfaces:')
        lines.append('')
        lines.extend('- `%s`: %s' % item for item in openings)
        lines.append('')
    failed = [(obj['object'], c['name']) for obj in objects for c in obj.get('checks', []) if not c.get('passed')]
    failed.extend(('Delivery', c['name']) for c in all_checks if not c.get('passed'))
    if failed:
        lines.extend(['Unresolved checks at this documentation checkpoint:', ''])
        lines.extend('- `%s`: %s' % item for item in failed)
        lines.append('')
    lines.extend([
        '## Rendering and resuming work', '',
        '`renders/hero.png` uses the final recipe of **%s × %s, Cycles, %s samples, denoised**. '
        '`renders/layout_top.png` provides a clear wide top-down layout. EEVEE checkpoint images support the build stages; '
        'the lighting/composition checkpoint is 1280 pixels wide. No detailed exterior is required.' %
            (dimensions[0], dimensions[1], samples), '',
        'To rebuild from scratch, open the embedded or standalone `LoungeBuilder.py` in Blender’s Text Editor, '
        'set `RUN_BUILD=True`, `BAKE_TEXTURES=True`, and `EXPORT=True`, adjust `PARAMETERS` if needed, and Run Script. '
        '`RUN_BUILD=False` loads the helper functions without automatically rebuilding. `BAKE_TEXTURES=False` skips '
        'texture baking for geometry iteration, and `EXPORT=False` skips FBX writes.', '',
        'For a checkpoint resume through Blender MCP, load the current script with `__name__` set to a non-main value '
        'so that it defines helpers without starting a full rebuild, then call `start_stage(N)` for the exact stage '
        'named in `PROGRESS.md`. Stages are: 1 blockout; 2 architecture; 3 furniture/props; 4 lighting/composition; '
        '5 optimize/unwrap/bake/export; 6 final renders/documentation/validation. `start_stage` schedules one coherent '
        'stage on Blender’s main thread and writes recoverable errors and the next resume step into the progress log. '
        'Wait for that stage to finish before submitting another.', '',
        'The builder is embedded in `Lounge.blend`; `PROGRESS.md` records the last successful action and exact resume '
        'step. `DECISIONS.md` records meaningful assumptions and deviations. Final validation is printed and saved '
        'to `Validation.md` and `Validation.json`, and the blend is saved after the final gate.', '',
        '**Studio upload/import was not performed.** The FBX, texture, geometry, UV, clearance, and render validations '
        'are performed in the local Blender delivery workflow. The Roblox light/material/collision assignments above '
        'must be applied during Studio assembly.', ''
    ])
    path = OUTPUT_DIR / 'Readme.md'
    path.write_text('\n'.join(lines), encoding='utf-8')
    return {'path': str(path), 'validation_status': status, 'documented_meshes': len(objects),
            'documented_texture_sets': actual_sets}
