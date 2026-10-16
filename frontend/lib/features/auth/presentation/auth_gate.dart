import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_error.dart';
// import '../../../core/navigation/last_route_storage.dart';
import '../../user/screens/screens.dart';
import '../../user/screens/welcome.dart';
import '../../user/screens/sessions.dart';
import '../../user/screens/home_shell.dart';

// import '../../home/presentation/home_screen.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
//import 'login_screen.dart';

/// Корневой виджет, который выбирает экран по состоянию AuthRepository
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // final _storage = LastRouteStorage();
  // String _lastRoute = LastRouteStorage.routeProjects;
  // // bool _routeLoaded = false;

  // @override
  // void initState() {
  //   super.initState();
  //   _lastRoute =
  //       LastRouteStorage.instance.current ?? LastRouteStorage.routeProjects;
  //   // _storage.get().then((r) {
  //   //   if (!mounted) return;
  //   //   setState(() {
  //   //     _lastRoute = r;
  //   //     _routeLoaded = true;
  //   //   });
  //   // });
  // }

  @override
  Widget build(BuildContext context) {
    // AuthGate перестраивается при каждом notifyListeners()
    final authRepository = context.watch<AuthRepository>();
    final state = authRepository.state;

    // if (!_routeLoaded) {
    //   return const _SplashScreen();
    // }

    // // Фоновое обновление
    // if (state is AuthLoading && state.isBackground) {
    //   return _screenForRoute(
    //     _lastRoute,
    //   ); //return const ProjectsScreen(); //HomeScreen(user: state.user!);
    // }

    return switch (state) {
      AuthUnknown() => const _SplashScreen(),

      AuthLoading() => const _SplashScreen(),

      AuthUnauthenticated() => const WelcomeScreen(),

      AuthAuthenticated() => const HomeShell(),
      // _screenForRoute(
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

  // Widget _screenForRoute(String route) {
  //   switch (route) {
  //     case LastRouteStorage.routeSessions:
  //       return const SessionScreen();
  //     case LastRouteStorage.routeProjects:
  //     default:
  //       return const ProjectsContent();
  //   }
  // }
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
