@tool
class_name BloodGpuMaterials
extends Resource
## Materials for the four shared GPU blood emitters.
## Empty slots inherit the defaults authored on the effect scene.

## Particle shader used by the manual emitters. A replacement must interpret
## their CUSTOM, COLOR, transform, and velocity payloads.
@export var process_material: Material
## Default draw material for mist and smoke particles.
@export var mist_material: Material
## Default draw material for the stretched blood sheets.
@export var sheets_material: Material
## Default draw material for individual droplets.
@export var drops_material: Material
## Default draw material for clot particles.
@export var clots_material: Material
