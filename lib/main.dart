// File: lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/emulator_config.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';
import 'services/device_service.dart';
import 'services/sensor_stream_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase:
  // 1. Jika mode emulator aktif (--dart-define=USE_FIREBASE_EMULATOR=true),
  //    gunakan EmulatorConfig.emulatorFirebaseOptions secara eksplisit.
  // 2. Jika mode cloud, gunakan DefaultFirebaseOptions.currentPlatform jika sudah dikonfigurasi.
  if (isEmulatorMode) {
    try {
      await Firebase.initializeApp(options: EmulatorConfig.emulatorFirebaseOptions);
      await configureEmulatorIfNeeded();
      await AuthService.instance.ensureAnonymousSession();
    } catch (e) {
      debugPrint('Firebase emulator init error: $e');
    }
  } else if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await AuthService.instance.ensureAnonymousSession();
    } catch (e) {
      debugPrint('Firebase cloud init / auth error: $e');
    }
  }

  // Sinkronkan ID perangkat yang tersimpan ke SensorStreamService
  final pairedId = await DeviceService.getPairedDeviceId();
  SensorStreamService.instance.setActiveDeviceId(pairedId);

  // Periksa status onboarding
  final hasOnboarded = await DeviceService.hasOnboarded();

  runApp(SimentriApp(initialOnboarded: hasOnboarded));
}

class SimentriApp extends StatelessWidget {
  final bool initialOnboarded;

  const SimentriApp({super.key, this.initialOnboarded = false});

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
      home: initialOnboarded
          ? const SplashScreen()
          : WelcomeScreen(
              onGetStarted: () async {
                await DeviceService.setOnboarded(true);
              },
            ),
    );
  }
}
