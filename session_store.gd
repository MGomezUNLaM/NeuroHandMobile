class_name PlayerSessionStore
extends Node

const SAVE_PATH := "user://player_data.json"
const WEEKLY_GOAL := 3
const MAX_XP_PER_LEVEL := 3000

var data: Dictionary = {
	"xp": 2350,
	"level": 12,
	"total_points": 12450,
	"streak_days": 15,
	"achievements": 24,
	"sessions": [],
}


func _ready() -> void:
	_load()


func save_session(taps: int, duration_sec: int) -> Dictionary:
	var xp_earned := taps * 2
	var session := {
		"timestamp": Time.get_unix_time_from_system(),
		"taps": taps,
		"duration_sec": duration_sec,
		"xp_earned": xp_earned,
		"score": taps,
	}
	data["sessions"].append(session)
	data["total_points"] = int(data["total_points"]) + xp_earned
	data["xp"] = int(data["xp"]) + xp_earned
	while int(data["xp"]) >= MAX_XP_PER_LEVEL:
		data["xp"] = int(data["xp"]) - MAX_XP_PER_LEVEL
		data["level"] = int(data["level"]) + 1
	_persist()
	
	# Guardar online en Supabase
	if Engine.has_singleton("SupabaseClient") or has_node("/root/SupabaseClient"):
		get_node("/root/SupabaseClient").insert_sesion_juego(taps)
	
	return session


func get_last_session() -> Dictionary:
	var sessions: Array = data.get("sessions", [])
	if sessions.is_empty():
		return {}
	return sessions[sessions.size() - 1]


func get_recent_sessions(count: int) -> Array:
	var sessions: Array = data.get("sessions", [])
	if sessions.is_empty():
		return []
	var start := maxi(0, sessions.size() - count)
	return sessions.slice(start)


func get_sessions_this_week() -> int:
	var sessions: Array = data.get("sessions", [])
	var now := Time.get_unix_time_from_system()
	var week_start := _week_start_unix(now)
	var total := 0
	for session in sessions:
		if int(session.get("timestamp", 0)) >= week_start:
			total += 1
	return total


func get_best_taps() -> int:
	var best := 0
	for session in data.get("sessions", []):
		best = maxi(best, int(session.get("taps", 0)))
	return best


func get_total_sessions() -> int:
	return data.get("sessions", []).size()


func get_average_taps() -> float:
	var sessions: Array = data.get("sessions", [])
	if sessions.is_empty():
		return 0.0
	var total := 0
	for session in sessions:
		total += int(session.get("taps", 0))
	return float(total) / float(sessions.size())


func get_total_xp_from_sessions() -> int:
	var total := 0
	for session in data.get("sessions", []):
		total += int(session.get("xp_earned", 0))
	return total


func format_session_date(timestamp: int) -> String:
	if timestamp <= 0:
		return ""
	var dict := Time.get_datetime_dict_from_unix_time(timestamp)
	var months := [
		"ene", "feb", "mar", "abr", "may", "jun",
		"jul", "ago", "sep", "oct", "nov", "dic",
	]
	return "%d %s · %02d:%02d" % [
		dict.day,
		months[dict.month - 1],
		dict.hour,
		dict.minute,
	]


func _week_start_unix(unix_time: int) -> int:
	var dict := Time.get_datetime_dict_from_unix_time(unix_time)
	var weekday: int = dict.weekday
	if weekday == 0:
		weekday = 7
	var days_back := weekday - 1
	return unix_time - days_back * 86400 - dict.hour * 3600 - dict.minute * 60 - dict.second


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key in parsed.keys():
			data[key] = parsed[key]
	if not data.has("sessions"):
		data["sessions"] = []


func _persist() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar la sesión.")
		return
	file.store_string(JSON.stringify(data, "\t"))
