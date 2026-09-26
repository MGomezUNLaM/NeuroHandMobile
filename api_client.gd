extends Node

## Cliente HTTP centralizado para la API de KINESIS en Azure.
## Maneja autenticación JWT, peticiones seguras y persistencia local de sesión.

signal login_succeeded(data: Dictionary)
signal login_failed(error_message: String, status_code: int)
signal forgot_password_succeeded(message: String)
signal forgot_password_failed(error_message: String, status_code: int)
signal patient_fetched(patient_data: Dictionary)
signal patient_fetch_failed(error_message: String, status_code: int)
signal patient_updated(patient_data: Dictionary)
signal patient_update_failed(error_message: String, status_code: int)
signal user_fetched(user_data: Dictionary)
signal auth_expired()

const BASE_URL := "https://api.kinesis.com.ar"
const AUTH_SAVE_PATH := "user://auth_token.json"

var access_token: String = ""
var token_type: String = "Bearer"
var expires_in: int = 86400
var is_remembered: bool = false

## Objeto completo de usuario retornado por GET /api/auth/me
var current_user: Dictionary = {}
## Objeto completo de paciente retornado por GET /api/patients/:id
var current_patient: Dictionary = {}

## Atributos individuales de /api/auth/me para acceso directo y tipado
var user_id: String = ""
var user_email: String = ""
var user_role: String = ""
var user_status: String = ""
var account_id: String = ""
var user_profile: Dictionary = {}
var patient_id: String = ""
var profile_type: String = ""
var first_name: String = ""
var last_name: String = ""
var full_name: String = ""


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
			
			# Validar obligatoriamente que el usuario tenga rol "PATIENT" en /api/auth/me
			_verify_patient_role(json_data)
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


func _verify_patient_role(auth_response: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			logout()
			login_failed.emit("No se pudo verificar el perfil del usuario (código %d)." % response_code, response_code)
			return
		
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not (parsed is Dictionary):
			logout()
			login_failed.emit("Error al procesar el perfil del usuario.", response_code)
			return
		
		_set_current_user(parsed)
		
		if user_role == "PATIENT":
			print("[ApiClient] Sesión de paciente iniciada con éxito.")
			if is_remembered:
				save_auth_data()
			else:
				clear_persisted_auth_file()
			
			user_fetched.emit(current_user)
			login_succeeded.emit(auth_response)
		else:
			logout()
			push_warning("[ApiClient] Acceso rechazado: El usuario no cuenta con perfil de paciente.")
			login_failed.emit("Acceso denegado: Esta aplicación es de uso exclusivo para pacientes.", 403)
	)
	
	var endpoint := BASE_URL + "/api/auth/me"
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		logout()
		login_failed.emit("Error de red al consultar el perfil de usuario.", 0)


func forgot_password(email: String) -> void:
	var clean_email := email.strip_edges()
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			forgot_password_failed.emit("Error de conexión. Verificá tu internet.", 0)
			return
		
		var body_text := body.get_string_from_utf8()
		var json_data: Variant = JSON.parse_string(body_text)
		
		if response_code >= 200 and response_code < 300:
			var msg := "Si el correo electrónico está registrado, recibirás las instrucciones para restablecer tu contraseña."
			forgot_password_succeeded.emit(msg)
		elif response_code == 400:
			forgot_password_failed.emit("Por favor, ingresá un correo electrónico válido.", response_code)
		else:
			forgot_password_failed.emit("No se pudo procesar la solicitud (código %d)." % response_code, response_code)
	)
	
	var endpoint := BASE_URL + "/api/auth/forgot-password"
	var request_headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var payload := {
		"email": clean_email
	}
	
	var json_body := JSON.stringify(payload)
	var err := http.request(endpoint, request_headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		forgot_password_failed.emit("No se pudo iniciar la conexión de red.", 0)


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
				_set_current_user(data)
				user_fetched.emit(current_user)
		elif response_code == 401:
			logout()
			auth_expired.emit()
	)
	
	var endpoint := BASE_URL + "/api/auth/me"
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()


func get_patient_profile(id_to_fetch: String = "") -> void:
	var target_id := id_to_fetch
	if target_id == "":
		target_id = patient_id
	if target_id == "":
		patient_fetch_failed.emit("No se encontró el identificador del paciente.", 0)
		return
	
	if not is_authenticated():
		patient_fetch_failed.emit("No hay sesión autenticada.", 401)
		return
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			patient_fetch_failed.emit("Error de conexión al cargar los datos del paciente.", 0)
			return
		
		var body_text := body.get_string_from_utf8()
		var json_data: Variant = JSON.parse_string(body_text)
		
		if response_code == 200 and json_data is Dictionary:
			current_patient = json_data
			if json_data.has("firstName"):
				first_name = str(json_data.get("firstName", ""))
			if json_data.has("lastName"):
				last_name = str(json_data.get("lastName", ""))
			if first_name != "" or last_name != "":
				full_name = ("%s %s" % [first_name, last_name]).strip_edges()
			patient_fetched.emit(current_patient)
		elif response_code == 401:
			logout()
			auth_expired.emit()
		else:
			var msg := "Error al obtener el perfil de paciente (código %d)." % response_code
			patient_fetch_failed.emit(msg, response_code)
	)
	
	var endpoint := BASE_URL + "/api/patients/" + target_id
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		patient_fetch_failed.emit("No se pudo iniciar la petición de red.", 0)


func update_patient_profile(data_to_update: Dictionary, id_to_update: String = "") -> void:
	var target_id := id_to_update
	if target_id == "":
		target_id = patient_id
	if target_id == "":
		patient_update_failed.emit("No se encontró el identificador del paciente.", 0)
		return
	
	if not is_authenticated():
		patient_update_failed.emit("No hay sesión autenticada.", 401)
		return
	
	# La regla del backend: A PATIENT can only update its own record and cannot change its status.
	# Eliminamos explícitamente el campo 'status' para evitar error 403
	var clean_data := data_to_update.duplicate(true)
	if clean_data.has("status"):
		clean_data.erase("status")
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			patient_update_failed.emit("Error de conexión al guardar los datos.", 0)
			return
		
		var body_text := body.get_string_from_utf8()
		var json_data: Variant = JSON.parse_string(body_text)
		
		if response_code >= 200 and response_code < 300 and json_data is Dictionary:
			current_patient = json_data
			if json_data.has("firstName"):
				first_name = str(json_data.get("firstName", ""))
			if json_data.has("lastName"):
				last_name = str(json_data.get("lastName", ""))
			if first_name != "" or last_name != "":
				full_name = ("%s %s" % [first_name, last_name]).strip_edges()
			
			# Sincronizar en memoria current_user.profile
			if current_user.has("profile") and current_user["profile"] is Dictionary:
				current_user["profile"]["firstName"] = first_name
				current_user["profile"]["lastName"] = last_name
			
			if is_remembered:
				save_auth_data()
			
			patient_updated.emit(current_patient)
		elif response_code == 409:
			patient_update_failed.emit("El correo electrónico o número de documento ya está registrado.", response_code)
		elif response_code == 400:
			var err_detail := "Datos inválidos. Por favor, revisá los campos ingresados."
			if json_data is Dictionary and json_data.has("message"):
				var m = json_data["message"]
				if m is Array and not m.is_empty():
					err_detail = str(m[0])
			patient_update_failed.emit(err_detail, response_code)
		elif response_code == 401:
			logout()
			auth_expired.emit()
		elif response_code == 403:
			patient_update_failed.emit("No tenés permisos para realizar esta operación.", response_code)
		else:
			patient_update_failed.emit("No se pudo actualizar el perfil (código %d)." % response_code, response_code)
	)
	
	var endpoint := BASE_URL + "/api/patients/" + target_id
	var json_body := JSON.stringify(clean_data)
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_PATCH, json_body)
	if err != OK:
		http.queue_free()
		patient_update_failed.emit("No se pudo iniciar la petición de red.", 0)


func logout() -> void:
	access_token = ""
	token_type = "Bearer"
	current_patient.clear()
	_set_current_user({})
	clear_persisted_auth_file()


## Parsea y almacena todos los campos devueltos por /api/auth/me
func _set_current_user(data: Dictionary) -> void:
	current_user = data
	user_id = str(data.get("id", ""))
	user_email = str(data.get("email", ""))
	user_role = str(data.get("role", "")).to_upper()
	user_status = str(data.get("status", ""))
	account_id = str(data.get("accountId", ""))
	
	var prof: Variant = data.get("profile", {})
	if prof is Dictionary:
		user_profile = prof
		patient_id = str(prof.get("id", ""))
		profile_type = str(prof.get("type", ""))
		first_name = str(prof.get("firstName", ""))
		last_name = str(prof.get("lastName", ""))
	else:
		user_profile = {}
		patient_id = ""
		profile_type = ""
		first_name = ""
		last_name = ""
	
	if first_name != "" or last_name != "":
		full_name = ("%s %s" % [first_name, last_name]).strip_edges()
	else:
		full_name = ""


# ── HELPERS DE AUTORIZACIÓN Y PERSISTENCIA ───────────────────────────────────

func is_authenticated() -> bool:
	return access_token != ""


func get_user_id() -> String:
	return user_id


func get_patient_id() -> String:
	return patient_id


func get_account_id() -> String:
	return account_id


func get_first_name() -> String:
	return first_name


func get_last_name() -> String:
	return last_name


func get_full_name() -> String:
	return full_name


func get_user_email() -> String:
	return user_email


func get_user_role() -> String:
	return user_role


func get_user_status() -> String:
	return user_status


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
		"currentUser": current_user,
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
		var saved_user: Dictionary = parsed.get("currentUser", {})
		# Si tenemos el usuario guardado y su rol NO es PATIENT, invalidar sesión
		if not saved_user.is_empty():
			var role: String = str(saved_user.get("role", "")).to_upper()
			if role != "PATIENT":
				clear_persisted_auth_file()
				return false
		
		access_token = str(parsed.get("accessToken", ""))
		token_type = str(parsed.get("tokenType", "Bearer"))
		expires_in = int(parsed.get("expiresIn", 86400))
		_set_current_user(saved_user)
		is_remembered = true
		return true
	
	return false


func clear_persisted_auth_file() -> void:
	if FileAccess.file_exists(AUTH_SAVE_PATH):
		DirAccess.remove_absolute(AUTH_SAVE_PATH)
