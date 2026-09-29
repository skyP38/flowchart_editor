import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'features/auth/data/api/auth_api.dart';
import 'features/auth/data/storage/secure_token_storage.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "http://localhost:8080",
  );

  final tokenStorage = SecureTokenStorage();

  late AuthRepository authRepository;

  final apiClient = ApiClient(
    baseUrl: baseUrl,
    storage: tokenStorage,
    onUnauthorized: () {
      authRepository.onSessionExpired();
    },
  );

  final authApi = AuthApi(apiClient);

  authRepository = AuthRepository(api: authApi, storage: tokenStorage);

  await authRepository.init();

  runApp(
    ChangeNotifierProvider<AuthRepository>.value(
      value: authRepository,
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
