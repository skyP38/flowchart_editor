// Package transport содержит общие HTTP-утилиты:
// middleware для логирования, CORS, ограничения тела, перехвата паник,
// а также хелперы для записи JSON-ответов
package transport

import (
	"log"
	"net/http"
	"strings"
	"time"
)

// Middleware - обертка над http.Handler
type Middleware func(http.Handler) http.Handler

// DefaultMaxBodyBytes - размер тела запроса по умолчанию
const DefaultMaxBodyBytes = 1 << 20 // 1 MiB

// BodyLimit ограничивает размер тела
// TODO: после добавления бизнес логики пересмотреть
func BodyLimit(defaultLimit int64, overrides map[string]int64) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Body == nil {
				next.ServeHTTP(w, r)
				return
			}
			limit := defaultLimit
			for prefix, l := range overrides {
				if strings.HasPrefix(r.URL.Path, prefix) {
					limit = l
					break
				}
			}
			// возвращение io.ReadCloser при превышении лимита
			r.Body = http.MaxBytesReader(w, r.Body, limit)
			next.ServeHTTP(w, r)
		})
	}
}

// Chain собирает цепочку вокруг обработчика
// Если mws пуст, h возвращается без изменений
func Chain(h http.Handler, mws ...Middleware) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

// Recover - для перехватки panic в нижележащих обработчиках
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic: %v", rec)
				WriteError(w, http.StatusInternalServerError, CodeInternal, "internal server error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// statusRecorder запоминает отправленный HTTP-статус ответа
// Используется в Logging, http.ResponseWriter не имеет встроенного метода для чтения статуса после записи
type statusRecorder struct {
	http.ResponseWriter
	status int
}

// WriteHeader сохраняет код статуса и передает запись нижележащему ResponseWriter
func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// Logging - для журналирования HTTP запросов
// Логируется строка вида: METHOD PATH STATUS DURATION
func Logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, rec.status, time.Since(start))
	})
}

// CORS - для добавления заголовков Cross-Origin Resource Sharing
// TODO: * - вообще это плохо, но пока нестрашно
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
