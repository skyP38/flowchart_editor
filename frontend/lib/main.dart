import 'package:flutter/material.dart';
import 'features/auth/presentation/register_screen.dart';

void main() {
  runApp(const MyApp());
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
      home: const RegistrationScreen(),
    );
  }
}
