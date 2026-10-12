import 'package:flutter/material.dart';
import 'package:my_test_app/screens/welcome_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const SimentriApp());
}

class SimentriApp extends StatelessWidget {
  const SimentriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIMETRI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003b73), // Dark blue primary
        ),
        useMaterial3: true,
        // fontFamily: 'Inter', // Uncomment if you add fonts to pubspec.yaml
      ),
      home: const WelcomeScreen(),
    );
  }
}
