// HTTP-заголовки и их значения, которые ставит клиент
abstract final class ApiHeaders {
  static const authorization = 'Authorization';
  static const bearerPrefix = 'Bearer ';

  // Готовая строка для заголовка Authorization
  static String bearer(String token) => '$bearerPrefix$token';
}
