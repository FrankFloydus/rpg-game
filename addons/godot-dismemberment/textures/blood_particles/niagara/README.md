# Bundled particle opacity maps

`compact_spray_film.png` and `head_spray_filaments.png` are independently
authored 768 × 768 linear grayscale opacity maps distributed under this
repository's license. The compact film uses a tapered spline, warped
apertures, a density ridge, and seeded breakup and droplets. The head
filaments use Bézier trajectories and tapered fluid cross-sections. The
generators read no input images.

The compact film map serves the shared Direction 04 liquid material used by
the artery and stab effects. The amputated limb scene uses its own
`stump_compact_spray_film.png` with the same Niagara material ID. The head filaments map serves the head
scene's DirectionalBurst003 layer. Each uses the existing bundled normal
map and material settings.

`forked_stump_film.png` refines the addon's original `forked_sheet.png`
with seeded variations in thickness, surface breakup, and perimeter droplets.
It serves DirectionalBurst001 in both amputated scenes. The source of the
refinement is the addon's distributable procedural mask.

`head_crescent_film.png` uses procedural tapered ligaments, an open curved
film, and spray droplets. Its generator reads no images. It serves the head
scene's DirectionalBurst layer. Both additional masks are 768 × 768 linear
grayscale textures distributed under the repository's license.

The current stump pulse, fork, crescent, and filament masks refine the
addon's earlier independent procedural textures. The revisions shift and
taper the existing forms, add seeded tapered ligaments, and blend a small
amount of the earlier masks back into the result. The generator uses only
repository-authored images and procedural geometry. The four 768 × 768
linear grayscale maps are distributed under the repository's license.

`dripping_spray_film.png` is an independently generated 768 × 768 linear
grayscale mask for the dynamic drip scene's BloodSquirt layer. Its open fan
uses tapered curves, suspended droplets, and seeded variations in film
density. The generator reads no image files. The mask is distributed under
the repository's license.

`masked_flow_normal.png` derives a shallow rounded surface and fine seeded
relief from the addon's independently authored droplet opacity. It serves
the visible Flow layers in Dripping Low, Med, and Dynamic. The local
reference importer uses the original material binding for these layers.

`dripping_flow_density.png` is an independently generated linear
grayscale map for Dripping Low, Med, and Dynamic. A rounded asymmetric
outline and soft pigment falloff set its coverage. It uses lossless
import with mipmaps and is distributed under the repository license.

`dripping_high_drop_density.png` and `dripping_high_drop_normal.png` are
independently generated masks and normals for Dripping High. A rounded,
slightly asymmetric profile defines the silhouette. The surface gradient
steers the existing reflection toward the rim. The density falls toward
the perimeter so the material darkens each droplet edge where drops
overlap. Both maps use lossless linear data with mipmaps and are
distributed under the repository license.

`liquid_cell.png` uses the same independently authored density profile as
Dripping High. It supplies all bundled translucent CellSpot layers and the
base masked material. Niagara shares a source shape across these materials.
The translucent material uses this profile for its own soft dissolve and
pigment response. The local reference importer keeps its original texture
bindings and cooked mip overrides.

`narrow_directional_jet.png` is an independently authored 768 × 384
linear density map for the Stab Drip layers. Its narrow strand widens
into layered ribbons with short seeded droplets. It uses lossless import
with mipmaps and is distributed under the repository license.

`radial_smooth_torn_sheet.png` is a 512 × 512 linear density map for
`MI_BloodSplash_04`. It combines the addon's original procedural sheet
with seeded tapered strands and a lighter film between the strands.
BulletHit Low and Med, all Slash tiers, and Stab Low and High use it for
MainBloodBurst. It uses lossless import with mipmaps and is distributed
under the repository license.

`crescent_sheet.png` is a 640 × 640 linear density map for
`MI_BloodDirection_08`. The revised map combines an asymmetric
procedural spline, a dense ridge, a thinner film, and seeded curved
ligaments with the addon's earlier mask. The generator reads only that
repository-authored mask. The texture uses lossless import with
mipmaps and is distributed under the repository license.

`curved_open_sheet.png` is a 640 × 640 linear density map for
`MI_BloodSplash_07`. The revision uses a curved liquid film, irregular
openings, and tapered ligaments, with seeded density variation and a
portion of the previous repository-authored ridge. The generator reads
only that previous mask. The texture uses lossless import with mipmaps
and is distributed under the repository license.
