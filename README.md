# Flowchart Editor



### TODO:
- cleanup истекших сессий;
- защита от перебора пароля
- ролевая модель user/admin (middleware)
- редактор бс
- управления активными сессиями (UI)
- панель администратора (пользователи, проекты)
- документированный REST API

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


