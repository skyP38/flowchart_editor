package transport

// ErrorResponse - стандартный формат ответа с ошибкой
type ErrorResponse struct {
	Error ErrorBody `json:"error"`
}

// ErrorBody - тело ошибки
//   - Code - идентификатор для обработки клиентом (например, "invalid_credentials", "login_taken")
//   - Message - человекочитаемое описание для отображения
//   - Details - пофайловые сообщения валидации (может не быть)
type ErrorBody struct {
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Details map[string]string `json:"details,omitempty"`
}

// Коды ошибок API
// Используются в поле error.code в JSON-ответах
const (
	// 400
	CodeInvalidInput = "invalid_input"

	// 401
	CodeUnauthorized        = "unauthorized"
	CodeInvalidCredentials  = "invalid_credentials"
	CodeInvalidRefreshToken = "invalid_refresh_token"
	CodeSessionRevoked      = "session_revoked"

	// 403
	CodeForbidden = "forbidden"

	// 404
	CodeSessionNotFound = "session_not_found"

	// 409
	CodeLoginTaken = "login_taken"

	// 429
	CodeTooManyRequests = "too_many_requests"

	// 500
	CodeInternal = "internal"
)
