import 'dart:async';

import 'package:flutter/material.dart';

import 'main_navigation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

    _controller.forward();

    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071426),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // LOGO SIMETRI
                  Center(
                    child: Image.asset('assets/simetri_logo.png', width: 180, fit: BoxFit.contain),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Memuat dashboard energi Anda...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xff9AA7BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // PROGRESS BAR
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: _controller.value,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff00D9A6)),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 25),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Mengambil data konsumsi energi dan status perangkat terhubung...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff9AA7BD), fontSize: 12, height: 1.5),
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
