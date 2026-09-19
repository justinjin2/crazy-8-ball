# Lounge Build Decisions

Record only material assumptions, scope cuts, deviations from the reference, and decisions needed to resume the build.

## Initial setup

- `reference.png` is the only visual reference. The original prompt mentioned a separate palette screenshot, but no such file is present; the written hex palette is authoritative.
- The existing table package remains in `../table/` and must not be modified or duplicated.

## Layout and authoring decisions

- Use 20-stud column pitch and 43-stud row pitch, with table centers X = −30, −10, 10, 30; Y = 0, 43, 86; floor Z = 0, 2.4, 4.8. Tables rotate +90° around native Z so their long axes face the hero camera. Shared unobstructed corridors satisfy ten studs between adjacent tables; requiring two independent ten-stud envelopes would instead require twenty-stud gaps.
- The 98 × 141 stud interior is longer and airier than the reference because table-to-step clearances require a minimum 42.56-stud row pitch. Each tier uses three 0.8 × 1.6 steps across an 80-stud stair width. Solid side guards are outside the playing envelopes.
- Window sill/head are relative to each occupied floor. Rear window heads stop at local 13.4 studs to fit beneath the allowed 14-stud mezzanine ceiling; the front/middle heads remain at local 15.
- Movable furniture retains base-centre placement translation, with rotation and scale applied. Architecture has a shared world-zero origin. Applying movable translation would erase its required pivot.
- The installed Blender MCP add-on was inactive and port 9876 belonged to a different bridge. Started the installed add-on on localhost:9877 for this session and confirmed tool discovery plus execute_blender_code in Blender 5.2.2. All build operations use that MCP tool through the local stdio client in scripts/mcp_call.py.
- Source table file has no source collection; its seven finished meshes are appended unchanged into one Table_Source collection, then instanced twelve times. Their packed materials remain untouched and table meshes are excluded from lounge exports and budgets.

## Composition and finish

- Extended the front foyer to native Y = −57 so the hero camera is inside the shell behind the lounge. The final interior is 98 × 163 studs; table centers and gameplay clearances are unchanged. The front entrance wall is hidden in presentation renders as an architectural cutaway but remains in the architecture export.
- All occupied floors keep their ceiling heights: main 18, middle 18 above the 2.4 tier, and rear 14 above the 4.8 tier. The ceiling follows those heights. Rear window heads are shortened as recorded above.
- Added removable low-poly ball racks and a 9.3-stud display cue over each finished table as separate lounge props. No source table geometry is rebuilt or exported.
- The sunset uses a procedural render-only colour backdrop and sun disks outside the right windows. It introduces no exterior asset or exported texture set. No detailed exterior, piano, vending machine, or outside trees is included.
- Omit Normal maps: restrained source variation, geometry bevels, and readable silhouettes provide the intended stylized finish. Bake actual AO at 32 samples and multiply it into colour at only 16%; do not bake direct illumination.

## Validation fixes and final gate

- The initial FBX reimport applied its axis conversion as an object rotation and introduced up to 0.000007629 stud of float error at the far end of the room. Reimporting with `bake_space_transform=True` preserves the same FBX authoring/export convention and yields zero world-vertex error across all 63 emissive meshes. The 1e-6-stud tolerance was retained.
- Exhaustive UV clipping found collapsed or folded micro-bevel triangles in the furniture and sign atlases. Those triangles receive individually isolated UV cells in a reserved strip, followed by rebaking and the same strict overlap/degeneracy test. No validation threshold was relaxed.
- Final gate: 233 exported meshes; 78,422 environment triangles; maximum 4,476 triangles per mesh; seven 1024² texture sets; twelve table instances; minimum measured clearance 10.11999893 studs; every mesh closed/manifold; all six aligned FBX packages; zero measured FBX round-trip error. All checks pass in Validation.json. Studio upload/import is outside this delivery and was not performed.
