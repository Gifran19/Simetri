import 'package:flutter/material.dart';

import '../services/device_service.dart';
import '../services/security_service.dart';
import '../utils/responsive.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({super.key, this.onSettingsChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = true;
  String _deviceToken = 'Memuat token...';
  bool _hasBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bioPref = await DeviceService.isBiometricEnabled();
    final hasBio = await SecurityService.hasBiometricSupport();
    final token = await SecurityService.getOrGenerateDeviceToken();

    if (!mounted) return;
    setState(() {
      _biometricEnabled = bioPref;
      _hasBiometrics = hasBio;
      _deviceToken = token;
    });
  }

  // ----------------------------------------------------
  // GANTI PIN KEAMANAN
  // ----------------------------------------------------
  Future<void> _showChangePinDialog() async {
    final authorized = await SecurityService.requestAuthorization(
      context: context,
      actionTitle: 'Ubah PIN Keamanan',
      actionDescription: 'Verifikasi identitas lama Anda sebelum memperbarui PIN.',
    );

    if (!authorized || !mounted) return;

    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xff0D1F3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: Color(0xff00D9A6)),
              SizedBox(width: 10),
              Text('PIN Keamanan Baru', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Masukkan 4 digit PIN baru yang mudah Anda ingat namun sulit ditebak orang lain.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xff071426),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Konfirmasi PIN',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13, letterSpacing: 0),
                  filled: true,
                  fillColor: const Color(0xff071426),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (pinController.text.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN harus terdiri dari 4 digit angka!')),
                  );
                  return;
                }
                if (pinController.text != confirmController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Konfirmasi PIN tidak cocok!')),
                  );
                  return;
                }

                await SecurityService.changePin(pinController.text);
                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xff0D1F3C),
                      content: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xff00D9A6)),
                          SizedBox(width: 8),
                          Text('PIN keamanan berhasil diperbarui!'),
                        ],
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff00D9A6)),
              child: const Text('Simpan PIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }



  // ----------------------------------------------------
  // LIHAT JEJAK AUDIT KEAMANAN
  // ----------------------------------------------------
  Future<void> _showAuditLogs() async {
    final logs = await SecurityService.getAuditLogs();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xff0D1F3C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_rounded, color: Color(0xff00D9A6)),
                          SizedBox(width: 8),
                          Text(
                            'Riwayat Keamanan',
                            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      CloseButton(color: Colors.white54),
                    ],
                  ),
                  const Text(
                    'Riwayat seluruh otorisasi kritis yang tersimpan secara terenkripsi:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(
                            child: Text('Belum ada jejak riwayat tersimpan.',
                                style: TextStyle(color: Colors.white38, fontSize: 13)),
                          )
                        : ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (ctx, index) => const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final item = logs[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.security_rounded, color: Color(0xff00D9A6), size: 18),
                                ),
                                title: Text(
                                  item['action'] ?? 'Aksi Keamanan',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  item['details'] ?? '',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                trailing: Text(
                                  item['time'] ?? '',
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xff071426),
      appBar: AppBar(
        backgroundColor: const Color(0xff071426),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(Icons.settings_suggest_rounded, color: Color(0xff00D9A6), size: 22),
            SizedBox(width: 8),
            Text('Pengaturan & Keamanan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 900,
          padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 14, vertical: 12),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              // SECTION 1: KEAMANAN & OTORISASI
              _buildSectionHeader('Keamanan & Otorisasi Pengguna'),
              _buildCardContainer([
                ListTile(
                  leading: const Icon(Icons.pin_rounded, color: Color(0xff00D9A6)),
                  title: const Text('Ubah PIN Keamanan', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Default PIN: 1234 • Terenkripsi di Keystore', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  onTap: _showChangePinDialog,
                ),
                const Divider(color: Colors.white10),
                SwitchListTile(
                  secondary: Icon(
                    Icons.fingerprint_rounded,
                    color: _hasBiometrics ? const Color(0xff00D9A6) : Colors.white30,
                  ),
                  title: const Text('Otentikasi Biometrik', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _hasBiometrics
                        ? 'Gunakan sidik jari atau wajah untuk aksi kritis'
                        : 'Sensor biometrik tidak tersedia di perangkat ini',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  value: _biometricEnabled && _hasBiometrics,
                  activeThumbColor: const Color(0xff00D9A6),
                  onChanged: _hasBiometrics
                      ? (val) async {
                          await DeviceService.saveBiometricEnabled(val);
                          setState(() => _biometricEnabled = val);
                        }
                      : null,
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.history_edu_rounded, color: Color(0xff00D9A6)),
                  title: const Text('Jejak Audit Keamanan', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Lihat 20 catatan log verifikasi keamanan terakhir', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  onTap: _showAuditLogs,
                ),
              ]),

              const SizedBox(height: 20),

              // SECTION 2: INFORMASI SMART METER IOT
              _buildSectionHeader('Informasi Perangkat IoT'),
              _buildCardContainer([
                ListTile(
                  leading: const Icon(Icons.memory_rounded, color: Color(0xff00D9A6)),
                  title: const Text('Perangkat & Sensor', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: const Text('ESP32 Dual-Core • PZEM-004T v3.0 AC', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.vpn_key_rounded, color: Color(0xff00D9A6)),
                  title: const Text('Hardware Pairing Key', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(_deviceToken, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ),
                const Divider(color: Colors.white10),
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: Color(0xff00D9A6)),
                  title: Text('Versi Aplikasi', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text('SIMETRI v1.2.0-sec (Material 3 Dark)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
              ]),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Color(0xff00D9A6), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildCardContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }
}