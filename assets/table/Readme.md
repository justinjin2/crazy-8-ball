Parametric tournament pool table — delivery notes

Built through the installed Blender MCP in Blender 5.2.2 LTS. The apron is plain, with no logo or lettering. The delivered default is the 9-foot playing surface; the embedded Python text and the standalone PoolTable.py contain all three presets.

Open PoolTable_9ft.blend. In the Text Editor, choose PoolTable.py, change PRESET to "7ft", "8ft", or "9ft", then Run Script. PARAMETERS contains the editable dimensions. RUN_BUILD=True and BAKE_TEXTURES=True rebuild the owned table scene, unwrap, bake and export beside the .blend. Set BAKE_TEXTURES=False for a quick geometry-only rebuild. OUTPUT_DIR controls delivery location. Source procedural materials remain available as SOURCE_* materials; each exported mesh uses one baked PBR material.

Coordinates: one Blender coordinate unit is one requested Roblox stud, with 0.16 stud per inch. Blender uses native Z-up, X-length, Y-width. The FBX uses -Z forward / Y up and transforms (x,y,z) to (x,z,-y), leaving X as length and exported Z as width. All mesh origins are (0,0,0) at the table centre on the floor; mesh transforms are applied. Empty locations intentionally carry the marker coordinates.

In Roblox Studio’s importer set File Geometry → Scale Unit to Stud and retain a scale factor of 1. The export uses FBX Unit Scale, so raw vertex coordinates retain stud values. The 9-foot footprint is 17.76 × 9.76 studs, the cloth is Y=2.9, the cushion noses are Y=3.16, and rail tops are Y=3.2328. [Roblox’s Blender import guidance](https://create.roblox.com/docs/art/blender) documents the Stud setting.

The specified cloth height is preserved: 2.9 studs equals 18.125 inches under this custom scale, giving shorter legs than the reference photograph. Corner offsets are 2.47 inches radially along the 45° diagonal, not 2.47 inches on each axis. “Top” means native +Y / exported −Z; Pocket1 is top-left and Pocket2 is the top side pocket. HeadSpot is at exported X=−4 and FootSpot at X=+4 for the 9-foot preset. Physics_9ft.json contains the full coordinates, exact nose segments and radii.

The 18 white diamond inlays are in a seventh mesh, Sights, to preserve both the white material and the single-material rule. Corner jaw length is measured along its plan face at 38° off the rail; side jaws are 13° off perpendicular. Short heel transitions meet the 1.8-inch cushion rear. The narrow side-pocket bridge limits the effective Rails bevel to 0.062 inches; other wood edges use the named 0.09-inch default. Cloth collars roll into the bore; black cup linings close at dark floors.

Final mesh counts:

| Object | Triangles |
|---|---:|
| Bed | 6,340 |
| Cushions | 1,088 |
| Rails | 4,176 |
| Pockets | 5,688 |
| Apron | 544 |
| Legs | 880 |
| Sights | 504 |
| Total | 19,220 |

Each asset mesh has one material, one non-overlapping UV map, no n-gons, and no live modifiers. The meshes are triangulated before FBX export; export triangulation is also enabled. Shared average texel density is approximately 36.53 pixels per stud at 1024². Minor local projection variation occurs on rounded edge surfaces. UV interior-overlap and bounds checks pass.

Textures: seven object-specific sets × five 1024 × 1024 PNG maps = 35 maps. BaseColor is sRGB; Normal, Roughness, Metalness and AO are data maps. Normal maps use tangent-space OpenGL (+Y). Metalness is zero. AO is a separate 256-sample Cycles bake and is not multiplied into BaseColor. All maps are packed in the .blend and supplied in textures/. For Roblox SurfaceAppearance, use each object’s BaseColor, Normal, Roughness and Metalness in their matching map slots. The *_bake.json files support resuming regeneration.

Presets measure cushion nose to cushion nose:

| PRESET | Playing length × width (in) | Outer length × width (in) |
|---|---|---|
| 9ft | 100 × 50 | 111 × 61 |
| 8ft | 88 × 44 | 99 × 55 |
| 7ft | 78 × 39 | 89 × 50 |

Every named geometry/UV parameter, with delivered defaults:

| Parameter | Default | Unit |
|---|---:|---|
| apron_bottom_chamfer_height | 0.55 | inches |
| apron_bottom_flare | 0.18 | inches |
| apron_height | 7 | inches |
| apron_inset | 0.28 | inches |
| apron_wall_thickness | 1.15 | inches |
| ball_diameter | 2.6 | inches |
| bed_lower_edge_inset | 0.65 | inches |
| bed_thickness | 2 | inches |
| bed_top_edge_inset | 0.08 | inches |
| casting_height | 0.16 | inches |
| casting_segments | 32 | segments |
| casting_width | 0.72 | inches |
| cloth_height | 2.9 | stud |
| cloth_hole_roll | 0.085 | inches |
| corner_facing_angle | 38 | degrees |
| corner_hole_diagonal_offset | 2.47 | inches |
| corner_hole_radius | 2.45 | inches |
| corner_mouth | 5.2 | inches |
| cushion_edge_bevel | 0.025 | inches |
| cushion_nose_height | 1.625 | inches |
| cushion_width | 1.8 | inches |
| facing_length | 1.6 | inches |
| hole_segments | 64 | segments |
| leg_bottom_width | 4.2 | inches |
| leg_corner_inset | 7 | inches |
| leg_top_overlap | 0.45 | inches |
| leg_top_width | 6.1 | inches |
| pocket_depth | 6.5 | inches |
| pocket_lining_thickness | 0.1 | inches |
| rail_base_below_cloth | 0.5 | inches |
| rail_height | 2.08 | inches |
| rail_width | 5.5 | inches |
| side_facing_angle | 13 | degrees |
| side_hole_offset | 2.73 | inches |
| side_hole_radius | 2.58 | inches |
| side_mouth | 5.72 | inches |
| sight_inset | 0.025 | inches |
| sight_long_diagonal | 0.52 | inches |
| sight_offset_from_nose | 3.55 | inches |
| sight_recess_border | 0.035 | inches |
| sight_short_diagonal | 0.26 | inches |
| spot_fraction_from_end | 0.25 | length fraction |
| studs_per_inch | 0.16 | stud/in |
| texture_resolution | 1024 | pixels |
| uv_pack_margin | 0.014 | UV fraction |
| wood_edge_bevel | 0.09 | inches |

Additional run controls: PRESET="9ft"; RUN_BUILD=True; BAKE_TEXTURES=True; OUTPUT_DIR defaults to the current .blend directory (or working directory if unsaved). The bake helper uses 16 samples for normal/PBR passes, 256 for AO, a 6-pixel extension margin, and non-overlapping UV packing before density normalization. Material grain, nap, color and roughness controls are named nodes in the retained SOURCE_* materials and defined in the same script.

Validation: successive 9→8→7→9 rebuilds checked dimensions, names, pockets, spots and nose ridges. The final 9-foot meshes were checked for manifoldness, zero-area faces, materials, UVs and transforms. FBX coordinates and a Blender reimport were checked at a tolerance of 0.000001 stud. Studio upload/import was not performed. Preview images show the baked materials; the render-only ground is excluded from the model.
