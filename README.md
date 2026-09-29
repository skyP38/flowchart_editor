# Flowchart Editor


Ожидаемые endpoint:
|Метод|Endpoint|Назначение|Тело запроса|Ответ|
|POST|/auth/register|Регистрация|login, name, password|AuthResponse|
|POST|/auth/login|Вход|login, password|AuthResponse|
|POST|/auth/refresh|Обновление access-токена|refreshToken|AuthTokens|
|POST|/auth/logout|Выход|refreshToken|204 / пустой ответ|
|GET|/auth/me|Текущий пользователь|—|User|
|GET|/auth/sessions|Активные сессии|—|список Session|
|DELETE|/auth/sessions/{id}|Завершить сессию|—|204|
|POST|/auth/password/request|Запрос сброса пароля|???|204|
|POST|/auth/password/confirm|Подтверждение сброса|token, newPassword|204|
