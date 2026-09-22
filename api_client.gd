extends Node

## Cliente HTTP centralizado para la API de KINESIS en Azure.
## Maneja autenticación JWT, peticiones seguras y persistencia local de sesión.

signal login_succeeded(data: Dictionary)
signal login_failed(error_message: String, status_code: int)
signal user_fetched(user_data: Dictionary)
signal auth_expired()

const BASE_URL := "https://api.kinesis.com.ar"
const AUTH_SAVE_PATH := "user://auth_token.json"

var access_token: String = ""
var token_type: String = "Bearer"
var expires_in: int = 86400
var current_user: Dictionary = {}
var is_remembered: bool = false


func _ready() -> void:
	load_auth_data()


# ── AUTENTICACIÓN ─────────────────────────────────────────────────────────────

func login(email: String, password: String, remember: bool = true) -> void:
	var clean_email := email.strip_edges()
	is_remembered = remember
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		_on_login_completed(http, result, response_code, headers, body)
	)
	
	var endpoint := BASE_URL + "/api/auth/login"
	var request_headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var payload := {
		"email": clean_email,
		"password": password
	}
	
	var json_body := JSON.stringify(payload)
	var err := http.request(endpoint, request_headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		login_failed.emit("No se pudo iniciar la conexión de red.", 0)


func _on_login_completed(http: HTTPRequest, result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http.queue_free()
	print("[ApiClient] Login response - Result: %d, HTTP Code: %d" % [result, response_code])
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var detail := ""
		match result:
			HTTPRequest.RESULT_CANT_CONNECT:
				detail = " (No se pudo conectar con el servidor)"
			HTTPRequest.RESULT_CANT_RESOLVE:
				detail = " (No se pudo resolver el dominio)"
			HTTPRequest.RESULT_CONNECTION_ERROR:
				detail = " (Error de socket/conexión)"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				detail = " (Error de certificado SSL/TLS)"
			HTTPRequest.RESULT_NO_RESPONSE:
				detail = " (Sin respuesta del servidor)"
			HTTPRequest.RESULT_TIMEOUT:
				detail = " (Tiempo de espera agotado)"
			_:
				detail = " (Código de error %d)" % result
		push_error("[ApiClient] Falló la petición de login: %s" % detail)
		login_failed.emit("Error de conexión%s. Verificá tu internet." % detail, 0)
		return
	
	var body_text := body.get_string_from_utf8()
	var json_data: Variant = JSON.parse_string(body_text)
	
	if response_code >= 200 and response_code < 300:
		if json_data is Dictionary and json_data.has("accessToken"):
			access_token = str(json_data.get("accessToken", ""))
			token_type = str(json_data.get("tokenType", "Bearer"))
			expires_in = int(json_data.get("expiresIn", 86400))
			
			if is_remembered:
				save_auth_data()
			else:
				clear_persisted_auth_file()
			
			# Consultar perfil del usuario autenticado
			get_me()
			
			login_succeeded.emit(json_data)
		else:
			login_failed.emit("Respuesta inesperada del servidor.", response_code)
	elif response_code == 401:
		var err_msg := "Correo electrónico o contraseña incorrectos."
		if json_data is Dictionary and json_data.has("message"):
			var server_msg: String = str(json_data.get("message", ""))
			if server_msg.to_lower().contains("invalid"):
				err_msg = "Correo electrónico o contraseña incorrectos."
			elif server_msg != "":
				err_msg = server_msg
		login_failed.emit(err_msg, response_code)
	elif response_code == 400:
		login_failed.emit("Por favor, ingresá un correo y contraseña válidos.", response_code)
	else:
		login_failed.emit("Error del servidor (código %d)." % response_code, response_code)


func get_me() -> void:
	if not is_authenticated():
		return
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var data: Variant = JSON.parse_string(body.get_string_from_utf8())
			if data is Dictionary:
				current_user = data
				user_fetched.emit(current_user)
		elif response_code == 401:
			logout()
			auth_expired.emit()
	)
	
	var endpoint := BASE_URL + "/api/auth/me"
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()


func logout() -> void:
	access_token = ""
	token_type = "Bearer"
	current_user.clear()
	clear_persisted_auth_file()


# ── HELPERS DE AUTORIZACIÓN Y PERSISTENCIA ───────────────────────────────────

func is_authenticated() -> bool:
	return access_token != ""


func get_auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: %s %s" % [token_type, access_token],
		"Content-Type: application/json",
		"Accept: application/json"
	])


func save_auth_data() -> void:
	var auth_dict := {
		"accessToken": access_token,
		"tokenType": token_type,
		"expiresIn": expires_in,
		"savedAt": Time.get_unix_time_from_system()
	}
	var file := FileAccess.open(AUTH_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(auth_dict, "\t"))


func load_auth_data() -> bool:
	if not FileAccess.file_exists(AUTH_SAVE_PATH):
		return false
	
	var file := FileAccess.open(AUTH_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("accessToken"):
		access_token = str(parsed.get("accessToken", ""))
		token_type = str(parsed.get("tokenType", "Bearer"))
		expires_in = int(parsed.get("expiresIn", 86400))
		is_remembered = true
		return true
	
	return false


func clear_persisted_auth_file() -> void:
	if FileAccess.file_exists(AUTH_SAVE_PATH):
		DirAccess.remove_absolute(AUTH_SAVE_PATH)
