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
signal treatment_fetched(treatment_data: Dictionary)
signal treatment_fetch_failed(error_message: String, status_code: int)
signal execution_saved(data: Dictionary)
signal execution_save_failed(error_message: String, status_code: int)
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
## Objeto completo del tratamiento retornado por GET /api/threatments/:id
var current_treatment: Dictionary = {}
## Sesiones activas vigentes para la fecha actual
var active_sessions: Array = []
## Actividades/juegos asignados en las sesiones vigentes de hoy con su dificultad
var active_activities: Array = []

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


# ── TRATAMIENTOS Y SESIONES ──────────────────────────────────────────────────

## Consulta el tratamiento asignado al paciente en /api/threatments (o /api/threatments/:id si se pasa un ID explícito).
## Filtra automáticamente las sesiones que están en fecha para hoy y sus actividades.
func get_treatment(id_to_fetch: String = "") -> void:
	if not is_authenticated():
		treatment_fetch_failed.emit("No hay sesión autenticada.", 401)
		return
	
	# Si no se provee id explícito, consultar directamente a la colección /api/threatments
	var endpoint_path := "/api/threatments"
	if id_to_fetch != "":
		endpoint_path = "/api/threatments/" + id_to_fetch
	
	_request_treatment_endpoint(endpoint_path, id_to_fetch, true)


func _request_treatment_endpoint(endpoint_path: String, id_param: String, allow_fallback: bool) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			treatment_fetch_failed.emit("Error de conexión al cargar el tratamiento.", 0)
			return
		
		# Si da 404 en threatments y allow_fallback es true, reintentar con treatments
		if response_code == 404 and allow_fallback and endpoint_path.contains("threatments"):
			var fallback_path := endpoint_path.replace("threatments", "treatments")
			print("[ApiClient] 404 en %s, reintentando con %s..." % [endpoint_path, fallback_path])
			_request_treatment_endpoint(fallback_path, id_param, false)
			return
		
		var body_text := body.get_string_from_utf8()
		var json_data: Variant = JSON.parse_string(body_text)
		
		if response_code >= 200 and response_code < 300:
			if json_data is Dictionary:
				current_treatment = json_data
			elif json_data is Array:
				current_treatment = {"treatments": json_data}
				if not json_data.is_empty() and json_data[0] is Dictionary:
					current_treatment = json_data[0]
			else:
				current_treatment = {}
			
			active_activities = _process_active_sessions(json_data)
			treatment_fetched.emit(current_treatment)
		elif response_code == 401:
			logout()
			auth_expired.emit()
		else:
			var msg := "Error al obtener el tratamiento (código %d)." % response_code
			treatment_fetch_failed.emit(msg, response_code)
	)
	
	var endpoint := BASE_URL + endpoint_path
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		treatment_fetch_failed.emit("No se pudo iniciar la petición de red.", 0)


## Procesa el árbol de tratamiento -> sesiones -> actividades, filtrando por el paciente actual y fecha actual.
func _process_active_sessions(payload: Variant) -> Array:
	active_sessions.clear()
	return _extract_active_activities(payload)


func _extract_active_activities(payload: Variant) -> Array:
	var activities_out: Array = []
	var now_dict := Time.get_date_dict_from_system() # Local date
	var today_str := "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]
	
	var all_sessions: Array = []
	if payload is Dictionary:
		# Si es un tratamiento, verificar si pertenece al paciente actual (si está definido)
		if patient_id != "" and payload.has("patientId"):
			var p_id := str(payload.get("patientId", ""))
			if p_id != "" and p_id != patient_id:
				return []
				
		if payload.has("sessions") and payload["sessions"] is Array:
			all_sessions = payload["sessions"]
		elif payload.has("sesiones") and payload["sesiones"] is Array:
			all_sessions = payload["sesiones"]
		elif payload.has("data") and payload["data"] is Dictionary:
			return _extract_active_activities(payload["data"])
		elif payload.has("data") and payload["data"] is Array:
			return _extract_active_activities(payload["data"])
	elif payload is Array:
		for item in payload:
			if item is Dictionary:
				# Si el array trae tratamientos de varios pacientes, filtrar por el del paciente logueado
				if patient_id != "" and item.has("patientId"):
					var p_id := str(item.get("patientId", ""))
					if p_id != "" and p_id != patient_id:
						continue
				var subs := _extract_active_activities(item)
				activities_out.append_array(subs)
		return activities_out
	
	for s_variant in all_sessions:
		if not (s_variant is Dictionary):
			continue
		var session: Dictionary = s_variant
		
		if _is_session_active_today(session, today_str):
			active_sessions.append(session)
			
			var s_diff: String = str(session.get("difficulty", session.get("dificultad", "medio"))).to_lower()
			
			# Buscar la lista de actividades de la sesión (sessionActivities, activities o actividades)
			var s_acts: Array = []
			if session.has("sessionActivities") and session["sessionActivities"] is Array:
				s_acts = session["sessionActivities"]
			elif session.has("activities") and session["activities"] is Array:
				s_acts = session["activities"]
			elif session.has("actividades") and session["actividades"] is Array:
				s_acts = session["actividades"]
			
			for a_variant in s_acts:
				if not (a_variant is Dictionary):
					continue
				var s_act: Dictionary = a_variant
				
				# En el backend, sessionActivities tiene:
				# id (sessionActivityId), difficulty, order, activity: { id, name, gameId, game: { id, name, ... } }
				var session_act_id: String = str(s_act.get("id", s_act.get("sessionActivityId", "")))
				var sess_id: String = str(session.get("id", session.get("sessionId", "")))
				
				var a_diff: String = str(s_act.get("difficulty", s_diff)).to_lower()
				var factor: float = get_difficulty_factor(a_diff)
				
				# Extraer datos de la actividad o del juego anidado
				var act_obj: Dictionary = s_act.get("activity", {}) if s_act.get("activity") is Dictionary else {}
				var game_obj: Dictionary = act_obj.get("game", {}) if act_obj.get("game") is Dictionary else {}
				
				var act_id: String = str(s_act.get("activityId", act_obj.get("id", session_act_id)))
				
				# Nombre: juego anidado -> actividad -> sessionActivity
				var act_name: String = str(game_obj.get("name", act_obj.get("name", s_act.get("name", ""))))
				
				# Tipo / GameId / Identificador de juego:
				var act_type: String = str(game_obj.get("id", act_obj.get("gameId", act_obj.get("type", s_act.get("type", "")))))
				
				var act_item := {
					"id": act_id,
					"sessionActivityId": session_act_id,
					"session_activity_id": session_act_id,
					"name": act_name,
					"type": act_type,
					"difficulty": a_diff,
					"difficulty_factor": factor,
					"session_id": sess_id,
					"raw": s_act
				}
				activities_out.append(act_item)
	
	return activities_out


## Verifica si una sesión corresponde mostrarse según availableUntil (menor o igual a la fecha de hoy).
func _is_session_active_today(session: Dictionary, today_str: String) -> bool:
	var end_val = session.get("availableUntil", session.get("endDate", session.get("fechaHasta", session.get("to", session.get("end_date", "")))))
	var start_val = session.get("availableFrom", session.get("startDate", session.get("fechaDesde", session.get("from", session.get("start_date", "")))))
	
	var e_str := str(end_val).strip_edges().substr(0, 10)
	var s_str := str(start_val).strip_edges().substr(0, 10)
	
	# Si no define fechas, se asume activa por defecto
	if e_str == "" and s_str == "":
		return true
	
	# La fecha availableUntil tiene que ser menor o igual a la fecha de hoy (vencimiento/disponibilidad alcanzada)
	if e_str != "" and e_str.length() == 10:
		return e_str <= today_str
	
	# Fallback por timestamp unix
	var now_unix := Time.get_unix_time_from_system()
	var end_unix := parse_date_to_unix(end_val, true)
	if end_unix > 0:
		return end_unix <= now_unix
	
	return true


## Convierte una fecha ISO o timestamp a unix timestamp en segundos.
func parse_date_to_unix(val: Variant, is_end_of_day: bool = false) -> int:
	if val is int or val is float:
		var n := int(val)
		if n > 1000000000000:
			n = n / 1000
		return n
	
	var s := str(val).strip_edges()
	if s == "":
		return 0
	
	if s.length() == 10 and s.count("-") == 2:
		s += "T23:59:59Z" if is_end_of_day else "T00:00:00Z"
	elif not s.contains("T") and s.contains(" "):
		s = s.replace(" ", "T")
	
	var has_tz: bool = s.ends_with("Z") or s.contains("+") or (s.length() > 10 and s.substr(10).contains("-"))
	if not has_tz:
		s += "Z"
	
	var unix_res := Time.get_unix_time_from_datetime_string(s)
	return maxi(0, unix_res)


## Retorna el factor multiplicador X para los umbrales de juego según la dificultad.
func get_difficulty_factor(difficulty_str: String) -> float:
	match difficulty_str.strip_edges().to_lower():
		"bajo", "low", "facil", "fácil", "1":
			return 0.8
		"alto", "high", "dificil", "difícil", "3":
			return 1.3
		_:
			return 1.0


# ── EJECUCIÓN DE ACTIVIDADES / SESIONES ──────────────────────────────────────

## Envía el resultado y las mediciones de la actividad a /api/session-activity-executions
func save_session_activity_execution(payload: Dictionary) -> void:
	if not is_authenticated():
		execution_save_failed.emit("No hay sesión autenticada para guardar la ejecución.", 401)
		return
	
	var http := HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			execution_save_failed.emit("Error de conexión al guardar los resultados.", 0)
			return
		
		var body_text := body.get_string_from_utf8()
		var json_data: Variant = JSON.parse_string(body_text)
		
		if response_code >= 200 and response_code < 300:
			print("[ApiClient] Ejecución guardada exitosamente en /api/session-activity-executions.")
			var res_dict: Dictionary = json_data if json_data is Dictionary else {}
			execution_saved.emit(res_dict)
		elif response_code == 401:
			logout()
			auth_expired.emit()
		else:
			var msg := "Error al guardar la ejecución (código %d): %s" % [response_code, body_text]
			push_warning(msg)
			execution_save_failed.emit(msg, response_code)
	)
	
	var endpoint := BASE_URL + "/api/session-activity-executions"
	var json_body := JSON.stringify(payload)
	var err := http.request(endpoint, get_auth_headers(), HTTPClient.METHOD_POST, json_body)
	if err != OK:
		http.queue_free()
		execution_save_failed.emit("No se pudo iniciar la petición de red.", 0)


func logout() -> void:
	access_token = ""
	token_type = "Bearer"
	current_patient.clear()
	current_treatment.clear()
	active_sessions.clear()
	active_activities.clear()
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
