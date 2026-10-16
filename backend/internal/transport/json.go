package transport

import (
	"encoding/json"
	"net/http"
)

// WriteJSON записывает JSON-ответ с указанным HTTP-статусом
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

func WriteError(w http.ResponseWriter, status int, code, message string) {
	WriteErrorDetails(w, status, code, message, nil)
}

// WriteErrorDetails записывает JSON-ответ с ошибкой в формате
//
//	{"error": {"code": "...", "message": "...", "details": {...}}}
func WriteErrorDetails(
	w http.ResponseWriter,
	status int,
	code, message string,
	details map[string]string,
) {
	WriteJSON(w, status, ErrorResponse{
		Error: ErrorBody{Code: code, Message: message, Details: details},
	})
}
