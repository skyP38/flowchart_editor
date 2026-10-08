import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_error.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import 'registration_screen.dart';
import 'widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  //final VoidCallback? onLoggedIn;
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isSubmitting = false;

  final Map<String, String> _fieldErrors = {};
  String? _generalError;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Сбрасывает ошибку конкретного поля при начале редактирования
  void _clearErrorFor(String field) {
    if (_fieldErrors.containsKey(field) || _generalError != null) {
      setState(() {
        _fieldErrors.remove(field);
        _generalError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final login = _loginController.text.trim();
    final password = _passwordController.text;

    // клиентская валидация
    final localErrors = <String, String>{};
    if (login.isEmpty) localErrors['login'] = 'Enter login';
    if (password.isEmpty) localErrors['password'] = 'Enter password';

    if (localErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(localErrors);
        _generalError = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _fieldErrors.clear();
      _generalError = null;
    });

    final repo = context.read<AuthRepository>();
    await repo.login(login: login, password: password);

    if (!mounted) return;

    // анализ результата
    final state = repo.state;
    ApiError? err;
    if (state is AuthUnauthenticated) err = state.error;
    if (state is AuthError) err = state.error;

    if (err == null) {
      debugPrint('login success, popping to root');
      //widget.onLoggedIn?.call();
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    _applyServerError(err);
  }

  // Раскладывает ошибку сервера
  void _applyServerError(ApiError err) {
    final newFieldErrors = <String, String>{};
    for (final field in const ['login', 'password']) {
      final msg = err.fieldError(field);
      if (msg != null) newFieldErrors[field] = msg;
    }

    setState(() {
      _isSubmitting = false;
      _fieldErrors
        ..clear()
        ..addAll(newFieldErrors);
      _generalError = newFieldErrors.isEmpty ? err.message : null;
    });
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegistrationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ), // Ограничение ширины для Web
            child: AuthCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLogoHeader(),
                  const SizedBox(height: 24),

                  // Заголовок
                  const Text(
                    'Sign in',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_generalError != null) ...[
                    AuthErrorBanner(_generalError!),
                    const SizedBox(height: 16),
                  ],

                  const AuthLabel('Login'),
                  AuthTextField(
                    controller: _loginController,
                    hintText: 'username',
                    enabled: !_isSubmitting,
                    errorText: _fieldErrors['login'],
                    onChanged: (_) => _clearErrorFor('login'),
                  ),
                  const SizedBox(height: 20),

                  const AuthLabel('Password'),
                  AuthTextField(
                    controller: _passwordController,
                    hintText: '••••••••',
                    obscureText: !_isPasswordVisible,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AuthColors.hint,
                        size: 20,
                      ),
                      onPressed: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  AuthPrimaryButton(
                    label: 'Login',
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _isSubmitting ? null : _goToRegister,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: const Text(
                            'No account? Register',
                            style: TextStyle(
                              color: AuthColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
