import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_error.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';
import 'widgets/auth_widgets.dart';
import '../domain/auth_limits.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _loginController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSubmitting = false;

  final Map<String, String> _fieldErrors = {};
  String? _generalError;

  @override
  void dispose() {
    _loginController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

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
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    // клиентская валидация
    final localErrors = <String, String>{};

    if (login.isEmpty) {
      localErrors['login'] = 'Enter login';
    } else if (login.length < AuthLimits.minLoginLength) {
      localErrors['login'] =
          'Login with at least ${AuthLimits.minLoginLength} characters';
    }

    if (name.isEmpty) {
      localErrors['name'] = 'Enter name';
    } else if (name.length < AuthLimits.minNameLength) {
      localErrors['name'] =
          'Name with at least ${AuthLimits.minNameLength} characters';
    }

    if (password.isEmpty) {
      localErrors['password'] = 'Enter password';
    } else if (password.length < AuthLimits.minPasswordLength) {
      localErrors['password'] =
          'Password with at least ${AuthLimits.minPasswordLength} characters';
    }

    if (confirm.isEmpty) {
      localErrors['confirmPassword'] = 'Repeat password';
    } else if (confirm != password) {
      localErrors['confirmPassword'] = 'Passwords don\'t match';
    }

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
    await repo.register(login: login, uname: name, password: password);

    if (!mounted) return;

    final state = repo.state;
    ApiError? err;
    if (state is AuthUnauthenticated) err = state.error;
    if (state is AuthError) err = state.error;

    if (err == null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    _applyServerError(err);
  }

  void _applyServerError(ApiError err) {
    final newFieldErrors = <String, String>{};
    for (final field in const [
      'login',
      'uname',
      'password',
      'confirmPassword',
    ]) {
      final msg = err.fieldError(field);
      if (msg != null) newFieldErrors[field] = msg;
    }
    final confirmFromServer = err.fieldError('confirm');
    if (confirmFromServer != null) {
      newFieldErrors.putIfAbsent('confirmPassword', () => confirmFromServer);
    }

    setState(() {
      _isSubmitting = false;
      _fieldErrors
        ..clear()
        ..addAll(newFieldErrors);
      _generalError = newFieldErrors.isEmpty ? err.message : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AuthDimensions.screenPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AuthDimensions.contentMaxWidth,
            ), // Ограничение ширины для Web
            child: AuthCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLogoHeader(),
                  const SizedBox(height: AuthDimensions.gapXxl),

                  const Text(
                    'Create account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AuthTypography.fontSizeTitle,
                      fontWeight: AuthTypography.weightBold,
                      color: AuthColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AuthDimensions.gapHuge),

                  if (_generalError != null) ...[
                    AuthErrorBanner(_generalError!),
                    const SizedBox(height: AuthDimensions.gapLg),
                  ],

                  const AuthLabel('Login'),
                  AuthTextField(
                    controller: _loginController,
                    hintText: 'username',
                    enabled: !_isSubmitting,
                    errorText: _fieldErrors['login'],
                    onChanged: (_) => _clearErrorFor('login'),
                  ),
                  const SizedBox(height: AuthDimensions.gapXl),

                  const AuthLabel('Name'),
                  AuthTextField(
                    controller: _nameController,
                    hintText: 'Ivanov Ivan Ivanovich',
                    enabled: !_isSubmitting,
                    errorText: _fieldErrors['name'],
                    onChanged: (_) => _clearErrorFor('name'),
                  ),
                  const SizedBox(height: AuthDimensions.gapXl),

                  const AuthLabel('Password'),
                  AuthTextField(
                    controller: _passwordController,
                    hintText: '••••••••',
                    obscureText: !_isPasswordVisible,
                    enabled: !_isSubmitting,
                    errorText: _fieldErrors['password'],
                    onChanged: (_) => _clearErrorFor('password'),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AuthColors.hint,
                        size: AuthDimensions.iconMd,
                      ),
                      onPressed: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible,
                      ),
                    ),
                  ),
                  const SizedBox(height: AuthDimensions.gapXl),

                  const AuthLabel('Confirm the password'),
                  AuthTextField(
                    controller: _confirmPasswordController,
                    hintText: '••••••••',
                    obscureText: !_isConfirmPasswordVisible,
                    enabled: !_isSubmitting,
                    errorText: _fieldErrors['confirmPassword'],
                    onChanged: (_) => _clearErrorFor('confirmPassword'),
                    onSubmitted: (_) => _submit(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AuthColors.hint,
                        size: AuthDimensions.iconMd,
                      ),
                      onPressed: () => setState(
                        () => _isConfirmPasswordVisible =
                            !_isConfirmPasswordVisible,
                      ),
                    ),
                  ),
                  const SizedBox(height: AuthDimensions.gapHuge),

                  AuthPrimaryButton(
                    label: 'Register',
                    isLoading: _isSubmitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AuthDimensions.gapXxl),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: const Text(
                            'Do you already have an account? Enter',
                            style: TextStyle(
                              color: AuthColors.primary,
                              fontSize: AuthTypography.fontSizeSm,
                              fontWeight: AuthTypography.weightMedium,
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
