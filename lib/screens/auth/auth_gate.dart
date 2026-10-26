// File: lib/screens/auth/auth_gate.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../main_navigation_screen.dart';
import '../welcome_screen.dart';
import 'login_screen.dart';

/// Gerbang Autentikasi Utama SIMETRI (Auth Gate).
///
/// Bertanggung jawab untuk:
/// 1. Memantau perubahan sesi Firebase Authentication (`authStateChanges`).
/// 2. Mengarahkan pengguna yang telah login langsung ke `MainNavigationScreen`.
/// 3. Mengarahkan pengguna yang belum login ke `WelcomeScreen` (jika baru pertama kali)
///    atau `LoginScreen` (jika sudah pernah membuka atau setelah logout).
/// 4. Memastikan sesi login cloud terisolasi dari otorisasi PIN lokal perangkat.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoadingPrefs = true;
  bool _hasOnboarded = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final onboarded = await DeviceService.hasOnboarded();
    if (!mounted) return;
    setState(() {
      _hasOnboarded = onboarded;
      _isLoadingPrefs = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrefs) {
      return const Scaffold(
        backgroundColor: Color(0xff071426),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xff00D9A6)),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        // Sedang memuat status sesi Firebase
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xff071426),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xff00D9A6)),
              ),
            ),
          );
        }

        // Pengguna telah terautentikasi -> Arahkan ke dashboard aplikasi yang sudah ada
        if (snapshot.hasData && snapshot.data != null) {
          return const MainNavigationScreen();
        }

        // Pengguna belum terautentikasi -> Cek apakah sudah pernah melewati welcome screen
        if (!_hasOnboarded) {
          return WelcomeScreen(
            onGetStarted: () async {
              await DeviceService.setOnboarded(true);
              if (mounted) {
                setState(() => _hasOnboarded = true);
              }
            },
          );
        }

        // Pengguna belum login dan sudah onboarded -> Halaman Login
        return const LoginScreen();
      },
    );
  }
}
