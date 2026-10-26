import 'package:flutter/material.dart';

import 'splash_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback? onGetStarted;

  const WelcomeScreen({super.key, this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071426),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(),

                        // LOGO
                        Column(
                          children: [
                            Image.asset('assets/logo.png', width: 240),
                            const SizedBox(height: 16),
                          ],
                        ),

                        // DESCRIPTION + BUTTON
                        Column(
                          children: [
                            const Text(
                              'Pantau konsumsi energi, kontrol perangkat pintar, dan hemat biaya bulanan Anda secara cerdas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xffB8C2D1), fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (onGetStarted != null) {
                                    onGetStarted!();
                                  }
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (context) => const SplashScreen()),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xff007BFF),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Get Started',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
