import 'package:flutter/material.dart';

import 'energy_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Shell Navigasi Terpadu SIMETRI menggunakan IndexedStack.
/// Memastikan transisi antar tab (Beranda, Analisis, Pengaturan) berlangsung instan (0 ms),
/// mempertahankan posisi scroll, dan tidak memicu inisialisasi ulang yang boros memori.
class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071426),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            onNavigateToTab: _onTabSelected,
            isInsideShell: true,
          ),
          EnergyScreen(
            onNavigateToTab: _onTabSelected,
            isInsideShell: true,
          ),
          SettingsScreen(
            onSettingsChanged: () {
              setState(() {});
            },
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff071426),
        border: Border(top: BorderSide(color: Color(0xff00D9A6), width: 1.0)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_rounded,
                label: 'Beranda',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.bolt_rounded,
                label: 'Analisis Energi',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.settings_rounded,
                label: 'Pengaturan',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xffffc400) : Colors.white54;

    return InkWell(
      onTap: () => _onTabSelected(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}