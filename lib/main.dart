import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase HANYA jika kredensial asli sudah diisi
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

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
