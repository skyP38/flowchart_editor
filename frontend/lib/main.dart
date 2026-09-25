import 'package:flutter/material.dart';
import 'screens/register_screen.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flowchart Editor Registration',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFFFF),
        fontFamily: 'Inter',
        colorScheme: .fromSeed(seedColor: const Color(0x6750A5)),
      ),
      home: const RegistrationScreen(),
    );
  }
}
