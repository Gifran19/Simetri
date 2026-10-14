import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 360;
        final imgWidth = isSmall ? 95.0 : 115.0;
        final imgHeight = isSmall ? 125.0 : 145.0;

        return Container(
          padding: EdgeInsets.all(isSmall ? 12 : 16),
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/simetri_logo.png',
                      width: isSmall ? 95 : 115,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selamat Datang,',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Smart Meter Online',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmall ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pantau penggunaan listrik rumah Anda secara real-time dan kapan saja.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isSmall ? 10 : 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/home.png',
                  width: imgWidth,
                  height: imgHeight,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}