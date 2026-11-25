# Blood deposit textures

The `pooled_*` and `spray_*` PNGs were copied byte-for-byte from Crimson Carnage's
`textures/effects/blood_deposits/` at commit `7026fca`. Its
`docs/architecture.md` records three generated grayscale atlases as the source
of the deposit silhouettes. The project used *Vermintide 2* footage and a
read-only study as visual references.

The `settled_pool_*` maps use connected wet bodies with broken edges and
porous patches. The `directional_fan`, `directional_drag`, and
`directional_streak` sets reframe Crimson Carnage's `pooled_08`, `pooled_06`,
and `pooled_02` maps, respectively. Their dense impact lies near the center
of the texture and the trail extends toward the bottom. The projected decal
aligns that axis with the incoming motion along the receiving surface.

The default `deposits.tres` uses 20 original high-resolution coverage
designs. The shapes range from disconnected fine spray to dense impacts,
directional splashes, and wall runoff. *Vermintide 2* was used for visual
comparison during testing. The single-target demo uses stock splatter 04.

Each design also has a 1024 × 1024 RGBA albedo for native Godot decals and a
512 × 512 tangent-space normal. Albedo alpha carries the coverage, including
the fine spray. Each normal uses its own mask to keep clear areas flat and
add fine, irregular relief inside denser marks. Its 256 × 256 ORM map packs
full occlusion, varying roughness, and zero metallic. Thicker areas tend to
reflect more strongly than the thin fringe.
Albedo RGB carries a bake of the original 256 × 256 `shared_grunge.png`.
The library supplies the blood tint at runtime. Native Godot decals pack the
individual textures into the renderer's decal atlas. The optional Surface
Finish receiver samples 2048 × 2048 coverage from a separate single-channel
texture array. It uses the shared grunge as a repeating detail texture.

The wall list has 14 compact splashes, three directional splashes, and
three runoff variants. Floors use the compact and directional designs
and two settled pool entries that reuse existing maps. Directional
variants follow the contact velocity, and runoff follows gravity. Each
design has an editable material in `materials/blood_decals/`. The six
stock particle-contact materials also use these maps. On the native decal
path, contact masks larger than 256 pixels keep their original texture
and fade opacity over time. Smaller masks can use cached dissolve frames.

Older standalone textures and materials remain available for existing
custom libraries.
