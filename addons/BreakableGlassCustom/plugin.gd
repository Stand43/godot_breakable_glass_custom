@tool
extends EditorPlugin

func _enter_tree():
	# Register the node as "BreakableGlassCustom"
	add_custom_type(
		"BreakableGlassCustom", 
		"CSGPolygon3D", 
		preload("breakable_glass_custom.gd"), 
		preload("icon.svg")
	)

func _exit_tree():
	# Clean up the specific type name
	remove_custom_type("BreakableGlassCustom")
