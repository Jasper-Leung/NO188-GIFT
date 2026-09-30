extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var a := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	print("create ok: ", a.get_size())
	var b := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	print("create_empty ok: ", b.get_size())
	b.set_pixel(3, 4, Color(0.2, 0.3, 0.4, 0.5))
	print("pixel: ", b.get_pixel(3, 4))
	var t := ImageTexture.create_from_image(b)
	print("tex size: ", t.get_size())
	quit(0)
