import 'package:flutter/material.dart';
import '../widgets/header_button.dart';
import 'package:provider/provider.dart';

import '../../auth/presentation/login_screen.dart';
import '../../auth/presentation/registration_screen.dart';
import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/domain/auth_state.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthRepository>().state;
    final message = state is AuthUnauthenticated ? state.message : null;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          if (message != null) _buildBanner(context, message),
          Container(
            height: 96,
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFD9D9D9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HeaderButton(
                  text: 'Log in',
                  background: const Color(0xFFE3E3E3),
                  borderColor: const Color(0xFF767676),
                  textColor: const Color(0xFF1E1E1E),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                ),

                const SizedBox(width: 12),
                HeaderButton(
                  text: 'Sign up',
                  background: const Color(0xFF6750A4),
                  borderColor: const Color(0xFF2C2C2C),
                  textColor: const Color(0xFFF5F5F5),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RegistrationScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: MediaQuery.sizeOf(context).width < 600 ? 40 : 160,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Flowchart Editor',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6750A4),
                        letterSpacing: -0.03 * 72,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Gost 19.701-90',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFFDED8E1),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      onPressed: () => LastRouteStorage.instance.setGuest(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6750A4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Try as guest',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFDECEC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB02A37), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB02A37), fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Color(0xFFB02A37), size: 18),
            onPressed: () => context.read<AuthRepository>().clearMessage(),
          ),
        ],
      ),
    );
  }
}
