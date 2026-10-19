// Ограничения валидации, синхронизированные с бэкендом
//   minUnameLen    = 1
//   minPasswordLen = 8
abstract final class AuthLimits {
  static const int minLoginLength = 1;

  static const int minNameLength = 1;

  static const int minPasswordLength = 8;
}
