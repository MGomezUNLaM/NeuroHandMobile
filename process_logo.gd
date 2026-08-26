extends SceneTree

func _init():
	var img = Image.load_from_file("res://assets/logo_kinesis.png")
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var w = img.get_width()
		var h = img.get_height()
		
		# Replace near-white pixels with transparent
		for y in range(h):
			for x in range(w):
				var c = img.get_pixel(x, y)
				if c.r > 0.9 and c.g > 0.9 and c.b > 0.9:
					c.a = 0.0
					img.set_pixel(x, y, c)
		
		# Crop bottom 35% to remove the text/slogan
		# We'll also crop a bit of the top/sides to center it better if we want,
		# but just cropping bottom is enough for now.
		var new_h = int(h * 0.65)
		var cropped = img.get_region(Rect2i(0, 0, w, new_h))
		
		cropped.save_png("res://assets/logo_kinesis_transparent.png")
		
		# Also save the original size but transparent for the login screen
		img.save_png("res://assets/logo_kinesis_transparent_full.png")
		print("IMAGE_PROCESSED")
	else:
		print("IMAGE_FAILED")
	quit()
