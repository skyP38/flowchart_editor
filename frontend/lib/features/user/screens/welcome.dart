import 'package:flutter/material.dart';
import '../widgets/header_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            height: 96,
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFD9D9D9)),
              ),
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
                    //TODO
                  },
                ),

                const SizedBox(width: 12),
                HeaderButton(
                  text: 'Sign up',
                  background: const Color(0xFF6750A4),
                  borderColor: const Color(0xFF2C2C2C),
                  textColor: const Color(0xFFF5F5F5),
                  onTap: () {
                    //TODO
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 160,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


