extends Node

const SUPABASE_URL := "https://ryhbvksqaqbydpscgrdw.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_LN2rLS7PlSBNOLV25Hs4Og_RhO1IY8k"

var _http_request: HTTPRequest

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


func insert_sesion_juego(taps: int, exercise_type: String = "flexion") -> void:
	var endpoint = SUPABASE_URL + "/rest/v1/sesion_juego"
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Prefer: return=minimal"
	]
	
	# La columna 'created_at' e 'id' se generarán automáticamente en Supabase.
	var data = {
		"cantidad_toques": taps,
		"tipo_ejercicio": exercise_type
	}
	
	var body = JSON.stringify(data)
	var error = _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("Error enviando datos a Supabase. Código interno: %s" % error)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code >= 200 and response_code < 300:
		print("✅ Sesión guardada exitosamente en Supabase. (HTTP ", response_code, ")")
	else:
		push_error("❌ Falló la petición a Supabase. HTTP Code: ", response_code)
		if body.size() > 0:
			push_error("Mensaje: ", body.get_string_from_utf8())
