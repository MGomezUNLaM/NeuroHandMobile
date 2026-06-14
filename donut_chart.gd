extends Control

const TRACK_COLOR := Color(0.06, 0.14, 0.28, 1)
const FILL_COLOR := Color(0.12, 0.82, 0.72, 1)
const GLOW_COLOR := Color(0.12, 0.82, 0.72, 0.25)

var value: float = 0.0
var max_value: float = 1.0
var center_title: String = "0/3"
var center_subtitle: String = "sesiones"


func set_progress(current: float, maximum: float, title: String = "", subtitle: String = "sesiones") -> void:
	value = current
	max_value = max(maximum, 0.001)
	center_title = title if title != "" else "%d/%d" % [int(current), int(maximum)]
	center_subtitle = subtitle
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.38
	var thickness: float = 14.0
	draw_circle(center, radius + 6.0, GLOW_COLOR)
	draw_arc(center, radius, 0.0, TAU, 72, TRACK_COLOR, thickness, true)
	var ratio: float = clampf(value / max_value, 0.0, 1.0)
	if ratio > 0.001:
		var start := -PI * 0.5
		var end := start + TAU * ratio
		draw_arc(center, radius, start, end, maxi(8, int(72 * ratio)), FILL_COLOR, thickness, true)
	var title_font := ThemeDB.fallback_font
	var title_size := 22
	var subtitle_size := 13
	var title_width := title_font.get_string_size(center_title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size).x
	var subtitle_width := title_font.get_string_size(center_subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1, subtitle_size).x
	draw_string(
		title_font,
		center - Vector2(title_width * 0.5, 6),
		center_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		title_size,
		Color(1, 1, 1, 1)
	)
	draw_string(
		title_font,
		center - Vector2(subtitle_width * 0.5, 24),
		center_subtitle,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		subtitle_size,
		Color(0.55, 0.62, 0.72, 1)
	)
