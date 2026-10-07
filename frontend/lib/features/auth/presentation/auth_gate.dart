import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_error.dart';
import '../../home/presentation/home_screen.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import 'login_screen.dart';

/// Корневой виджет, который выбирает экран по состоянию AuthRepository
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // AuthGate перестраивается при каждом notifyListeners()
    final authRepository = context.watch<AuthRepository>();
    final state = authRepository.state;

    // Фоновое обновление
    if (state is AuthLoading && state.isBackground) {
      return HomeScreen(user: state.user!);
    }

    return switch (state) {
      AuthUnknown() => const _SplashScreen(),

      AuthLoading() => const _SplashScreen(),

      AuthUnauthenticated() => LoginScreen(onLoggedIn: () {}),

      AuthAuthenticated(:final user) => HomeScreen(user: user),

      AuthError(:final error) => _AuthErrorScreen(
        error: error,
        onRetry: () => context.read<AuthRepository>().init(),
      ),
    };
  }
}

// экран-заглушка на время восстановления сессии/загрузки
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// Экран ошибки восстановления сессии: сообщение + кнопка Повторить
class _AuthErrorScreen extends StatelessWidget {
  final ApiError error;
  final VoidCallback onRetry;

  const _AuthErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  "Couldn't restore session",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Repeat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
