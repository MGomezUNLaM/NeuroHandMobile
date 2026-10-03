import datetime
import json

def parse_date_to_unix(val, is_end_of_day=False):
    if isinstance(val, (int, float)):
        n = int(val)
        if n > 1000000000000:
            n //= 1000
        return n
    s = str(val).strip()
    if not s:
        return 0
    if len(s) == 10 and s.count("-") == 2:
        s += "T23:59:59Z" if is_end_of_day else "T00:00:00Z"
    elif "T" not in s and " " in s:
        s = s.replace(" ", "T")
    if not s.endswith("Z") and "+" not in s and "-" not in s[10:]:
        s += "Z"
    
    # parse ISO
    dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return int(dt.timestamp())

def get_difficulty_factor(diff_str):
    d = diff_str.strip().lower()
    if d in ["bajo", "low", "facil", "fácil", "1"]:
        return 0.8
    elif d in ["alto", "high", "dificil", "difícil", "3"]:
        return 1.3
    return 1.0

def is_session_active(session, now_unix):
    start_val = session.get("startDate", session.get("fechaDesde", ""))
    end_val = session.get("endDate", session.get("fechaHasta", ""))
    if not start_val and not end_val:
        return True
    start_unix = parse_date_to_unix(start_val, False)
    end_unix = parse_date_to_unix(end_val, True)
    if start_unix > 0 and now_unix < start_unix:
        return False
    if end_unix > 0 and now_unix > end_unix:
        return False
    return True

# Test cases
now = int(datetime.datetime.now(datetime.timezone.utc).timestamp())

session_active = {
    "id": "s1",
    "startDate": "2026-10-01",
    "endDate": "2026-10-10",
    "difficulty": "alto",
    "activities": [{"name": "Flappy Bird", "type": "flexion"}]
}

session_expired = {
    "id": "s2",
    "startDate": "2026-09-01",
    "endDate": "2026-09-15",
    "difficulty": "medio"
}

session_future = {
    "id": "s3",
    "startDate": "2026-11-01",
    "endDate": "2026-11-15",
    "difficulty": "bajo"
}

assert is_session_active(session_active, now) == True, "s1 should be active"
assert is_session_active(session_expired, now) == False, "s2 should be expired"
assert is_session_active(session_future, now) == False, "s3 should be future"

assert get_difficulty_factor("bajo") == 0.8
assert get_difficulty_factor("medio") == 1.0
assert get_difficulty_factor("alto") == 1.3

print("ALL LOGIC TESTS PASSED!")
