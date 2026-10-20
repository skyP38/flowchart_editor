import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_error.dart';
import '../../user/screens/welcome.dart';
import '../../user/screens/home_shell.dart';
import '../../admin/presentation/admin_shell.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';

import 'widgets/auth_dimensions.dart';
import 'widgets/auth_typ.dart';
import '../../../core/navigation/last_route_storage.dart';
import '../../user/screens/guest_editor_screen.dart';

// Корневой виджет, который выбирает экран по состоянию AuthRepository
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    // AuthGate перестраивается при каждом notifyListeners()
    final authRepository = context.watch<AuthRepository>();
    final routeStorage = context.watch<LastRouteStorage>();
    final state = authRepository.state;

    return switch (state) {
      AuthUnknown() => const _SplashScreen(),

      AuthLoading() => const _SplashScreen(),

      AuthUnauthenticated() =>
        routeStorage.isGuest
            ? const GuestEditorScreen()
            : const WelcomeScreen(),

      AuthAuthenticated(:final user) =>
        user.role?.toLowerCase() == 'admin' ? const AdminShell() : const HomeShell(), // _screenForRoute(
      // _lastRoute,
      // ), //const ProjectsScreen(),
      //AuthUnauthenticated() => LoginScreen(onLoggedIn: () {}),

      // AuthAuthenticated(:final user) =>
      //  const ProjectsScreen(), // HomeScreen(user: user),
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
          constraints: const BoxConstraints(
            maxWidth: AuthDimensions.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AuthDimensions.screenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: AuthDimensions.iconXl,
                  color: colorScheme.error,
                ),
                const SizedBox(height: AuthDimensions.gapLg),
                Text(
                  "Couldn't restore session",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AuthDimensions.gapSm),
                Text(
                  error.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AuthDimensions.gapXxl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AuthDimensions.buttonVerticalPadding,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AuthDimensions.radiusSm,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Repeat',
                      style: TextStyle(
                        fontSize: AuthTypography.fontSizeLg,
                        fontWeight: AuthTypography.weightSemiBold,
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
