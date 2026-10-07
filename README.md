# Flowchart Editor



### TODO:
- подключение БД
- валидация конфига
- редактор бс
- управления активными сессиями (UI)
- панель администратора (пользователи, проекты)
- документированный REST API
- HTTPS и управление сертификатами

Ожидаемые endpoint:
|Метод|Endpoint|Назначение|Тело запроса|Ответ|
|---|---|---|---|---|
|POST|/api/auth/register|Регистрация|login, name, password|AuthResponse|
|POST|/api/auth/login|Вход|login, password|AuthResponse|
|POST|/api/auth/refresh|Обновление access-токена|refreshToken|AuthTokens|
|POST|/api/auth/logout|Выход|refreshToken|204 / пустой ответ|
|GET|/api/auth/me|Текущий пользователь|-|User|
|GET|/api/sessions|Активные сессии|-|список Session|
|DELETE|/api/sessions/{id}|Завершить сессию|-|204|
|DELETE|/api/sessions/|Завершить все сессии кроме текущей|-|???|

с назначением проекта, требованиями к окружению и командами запуска,
сборки и тестирования;

```bash
go run ./cmd/server
```
По умолчанию слушает :8080

Проверка:

```bash
  curl http://localhost:8080/health
  # {"status":"ok"}
```


## Переменные окружения

| Переменная                   | По умолчанию | Назначение                    |
| ---------------------------- | -----------: | ----------------------------- |
| `APP_PORT`                   |       `8080` | Порт сервера                  |
| `JWT_SECRET`                 |  `change-me` | Секрет для подписи JWT        |
| `PASSWORD_PEPPER`            |  `change-me` | Pepper для bcrypt             |
| `ACCESS_TOKEN_TTL`           |        `15m` | Время жизни access-токена     |
| `REFRESH_TOKEN_TTL`          |       `168h` | Время жизни refresh-токена    |
| `ADMIN_LOGIN`                |      `admin` | Логин администратора          |
| `ADMIN_PASSWORD`             |      `admin` | Пароль администратора         |
| `LOGIN_MAX_ATTEMPTS`         |          `5` | Попыток логина до блокировки  |
| `LOGIN_WINDOW`               |        `15m` | Окно подсчёта попыток         |
| `LOGIN_BLOCK_DURATION`       |        `15m` | Базовая блокировка            |
| `LOGIN_MAX_BLOCK_COUNT`      |          `4` | Потолок множителя блокировки  |
| `LOGIN_DECAY_WINDOW`         |        `24h` | Забывание счётчика блокировок |
| `RATELIMIT_CLEANUP_INTERVAL` |         `5m` | Очистка rate limiter          |
| `SESSION_CLEANUP_INTERVAL`   |         `5m` | Очистка сессий                |
| `SESSION_RETENTION`          |        `24h` | Хранение просроченных сессий  |

## API

### Health

```http
curl -i http://localhost:8080/health # GET /health
```

Ответ:
```json
{"status":"ok"}
```

### Регистрация

```http
# POST /api/auth/register
curl -i -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"login":"user123","uname":"User Name","password":"password1"}'
```

Ответ:
```json
HTTP/1.1 201 Created

{
  "user": {
    "id": 2,
    "login":"user123",
    "uname":"User Name",
    "role":"user"
  },
  "access_token":"...",
  "refresh_token":"...",
  "expires_in":900
}
```

### Вход

```http
# POST /api/auth/login
curl -i -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"login":"user123","password":"password1"}'
```

Ответ:
```json
HTTP/1.1 200 OK

{
  "user": {
    "id": 2,
    "login":"user123",
    "uname":"User Name",
    "role":"user"
  },
  "access_token":"...",
  "refresh_token":"...",
  "expires_in":900
}
```

### Обновление access-токена

```http
# POST /api/auth/refresh
curl -i -X POST http://localhost:8080/api/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "..."}'
```

Ответ:
```json
HTTP/1.1 200 OK

{
  "user": {
    "id": 2,
    "login":"user123",
    "uname":"User Name",
    "role":"user"
  },
  "access_token":"...",
  "refresh_token":"***",
  "expires_in":900
}
```


### Выход

```http
# POST /api/auth/logout
curl -i -X POST http://localhost:8080/api/auth/logout \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "..."}'
```

Ответ: `HTTP/1.1 204 No Content`


### Текущий пользователь

```http
# GET /api/auth/me
curl -i http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer <access_token>"
```

Ответ:
```json
HTTP/1.1 200 OK

{
  "id": 1,
  "login": "user123",
  "uname": "User Name",
  "role": "user"
}
```


### Сессии

```http
# GET /api/sessions
curl -i http://localhost:8080/api/sessions \
  -H "Authorization: Bearer <access_token>"
```
Ответ:
```json
HTTP/1.1 200 OK

{
  "sessions": [
    {
      "id":1,
      "created_at":"2026-10-07T21:31:08.810996291Z",
      "expires_at":"2026-10-14T21:31:08.810996291Z",
      "active":true,
      "current":false
    }, <...> {
      "id":6,
      "created_at":"2026-10-07T21:46:20.750916174Z",
      "expires_at":"2026-10-14T21:46:20.750916174Z",
      "active":true,
      "current":true
    }
  ]
}
```


```http
# DELETE /api/sessions/{id}
curl -i -X DELETE http://localhost:8080/api/sessions/{id} \
  -H "Authorization: Bearer <access_token>"
```
Ответ:
```json
HTTP/1.1 204 No Content
```


```http
# DELETE /api/sessions - отозвать все сессии кроме текущей
curl -i -X DELETE http://localhost:8080/api/sessions \
  -H "Authorization: Bearer <access_token>"
```
Ответ:
```json
HTTP/1.1 204 No Content
```


### Админ-статистика

```http
# GET /api/admin/stats

curl -i http://localhost:8080/api/admin/stats \
  -H "Authorization: Bearer <admin_access_token>"
```

Ответ:
```json
HTTP/1.1 200 OK

{
  "sessions": {
    "total": 9,
    "active": 3,
    "revoked": 6,
    "expired": 0
  }
}
```


## Структура

backend:
```
.
├── cmd # точка входа
│   └── server
│       └── main.go
├── go.mod
├── go.sum
└── internal
    ├── api # HTTP-обработчики и middleware
    │   ├── admin_handler.go
    │   ├── auth_handler.go
    │   ├── middleware.go
    │   └── session_handler.go
    ├── config # конфигурация
    │   └── config.go
    ├── domains # доменные модели и интерфейсы
    │   ├── errors.go
    │   ├── login.go
    │   ├── repositories.go
    │   ├── session.go
    │   └── user.go
    ├── service
    │   ├── auth # аутентификация и токены
    │   │   ├── errors.go
    │   │   ├── service.go
    │   │   └── token
    │   │       ├── access.go
    │   │       └── refresh.go
    │   ├── password # хеширование паролей
    │   │   └── password.go
    │   ├── ratelimit # rate limiting
    │   │   ├── errors.go
    │   │   ├── memory.go
    │   │   ├── policy.go
    │   │   └── ratelimit.go
    │   └── sessioncleanup # очистка сессий
    │       └── janitor.go
    ├── storage
    │   └── memory # in-memory реализации
    │       ├── errors.go
    │       ├── seed.go
    │       ├── session_repo.go
    │       ├── session_stats.go
    │       └── user_repo.go
    └── transport # HTTP-утилиты и middleware
        ├── errors.go
        ├── json.go
        └── middleware.go
```


frontend

```text
├── lib
│   ├── core
│   │   └── network
│   │       ├── api_client.dart
│   │       ├── api_error.dart
│   │       ├── interceptors
│   │       │   ├── auth_interceptor.dart
│   │       │   ├── error_interceptor.dart
│   │       │   └── refresh_interceptor.dart
│   │       └── token_storage.dart
│   ├── features
│   │   ├── auth
│   │   │   ├── data
│   │   │   │   ├── api
│   │   │   │   │   └── auth_api.dart
│   │   │   │   ├── models
│   │   │   │   │   ├── auth_response.dart
│   │   │   │   │   ├── auth_tokens.dart
│   │   │   │   │   ├── session.dart
│   │   │   │   │   └── user.dart
│   │   │   │   └── storage
│   │   │   │       └── secure_token_storage.dart
│   │   │   ├── domain
│   │   │   │   ├── auth_repository.dart
│   │   │   │   └── auth_state.dart
│   │   │   └── presentation
│   │   │       ├── auth_gate.dart
│   │   │       ├── login_screen.dart
│   │   │       ├── registration_screen.dart
│   │   │       └── widgets
│   │   │           ├── auth_card.dart
│   │   │           ├── auth_colors.dart
│   │   │           ├── auth_error_banner.dart
│   │   │           ├── auth_label.dart
│   │   │           ├── auth_logo_header.dart
│   │   │           ├── auth_primary_button.dart
│   │   │           ├── auth_text_field.dart
│   │   │           └── auth_widgets.dart
│   │   └── home
│   │       └── presentation
│   │           └── home_screen.dart
│   └── main.dart
├── pubspec.lock
└──  pubspec.yaml
```
