import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/network/api_service.dart';
import 'core/navigation/last_route_storage.dart';
// import 'core/navigation/route_observer.dart';
import 'features/auth/data/api/auth_api.dart';
import 'features/admin/data/admin_api.dart';
import 'features/auth/data/storage/secure_token_storage.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LastRouteStorage.instance.init();

  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "http://localhost:8080",
  );

  final tokenStorage = SecureTokenStorage();

  late final ApiClient apiClient;
  late final AuthApi authApi;
  late final AdminApi adminApi;
  late final ApiService apiService;
  late final AuthRepository authRepository;

  apiClient = ApiClient(
    baseUrl: baseUrl,
    storage: tokenStorage,
    onUnauthorized: () => authRepository.onSessionExpired(
      reason: 'Your session has expired. Please sign in again.',
    ),
    onUserBlocked: () => authRepository.onSessionExpired(
      reason: 'Your account has been blocked. Contact an administrator.',
    ),
  );

  authApi = AuthApi(apiClient);
  adminApi = AdminApi(apiClient);
  apiService = ApiService(apiClient);

  authRepository = AuthRepository(api: authApi, storage: tokenStorage);

  await authRepository.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthApi>.value(value: authApi),
        Provider<AdminApi>.value(value: adminApi),
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider<AuthRepository>.value(value: authRepository),
        ChangeNotifierProvider<LastRouteStorage>.value(
          value: LastRouteStorage.instance,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flowchart Editor',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A5)),
      ),
      home: const AuthGate(),
    );
  }
}
