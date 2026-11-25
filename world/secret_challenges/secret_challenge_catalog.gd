extends RefCounted
## Fixed route listing so the authored layouts are included in exported games.

const Route := preload("res://world/secret_challenges/secret_challenge_route.gd")

const ROUTES: Array[Route] = [
	preload("res://world/secret_challenges/routes/ember_step.tres"),
	preload("res://world/secret_challenges/routes/iron_latch.tres"),
	preload("res://world/secret_challenges/routes/choking_loop.tres"),
	preload("res://world/secret_challenges/routes/old_horn_duct.tres"),
	preload("res://world/secret_challenges/routes/kiln_shelf.tres"),
	preload("res://world/secret_challenges/routes/twin_bridges.tres"),
	preload("res://world/secret_challenges/routes/ossuary_hook.tres"),
	preload("res://world/secret_challenges/routes/pale_hinges.tres"),
	preload("res://world/secret_challenges/routes/soot_well.tres"),
	preload("res://world/secret_challenges/routes/ashward_return.tres"),
	preload("res://world/secret_challenges/routes/penitent_teeth.tres"),
	preload("res://world/secret_challenges/routes/peat_windows.tres"),
	preload("res://world/secret_challenges/routes/grave_loom.tres"),
	preload("res://world/secret_challenges/routes/saints_duct.tres"),
	preload("res://world/secret_challenges/routes/cinder_glass.tres"),
	preload("res://world/secret_challenges/routes/bellsmith_gallery.tres"),
	preload("res://world/secret_challenges/routes/red_recesses.tres"),
	preload("res://world/secret_challenges/routes/votive_crossing.tres"),
	preload("res://world/secret_challenges/routes/broken_crucible.tres"),
	preload("res://world/secret_challenges/routes/last_teeth.tres"),
]
