import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff071426),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff00D9A6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}
