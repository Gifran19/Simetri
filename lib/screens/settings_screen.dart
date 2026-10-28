import 'package:flutter/material.dart';

import '../services/device_service.dart';
import '../services/security_service.dart';
import '../services/sensor_stream_service.dart';
import '../utils/responsive.dart';
import '../widgets/connect_device_sheet.dart';

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

  // ----------------------------------------------------
  // MANAJEMEN PAIRING PERANGKAT
  // ----------------------------------------------------
  Future<void> _showDisconnectDeviceDialog() async {
    final authorized = await SecurityService.requestAuthorization(
      context: context,
      actionTitle: 'Putuskan Perangkat',
      actionDescription: 'Verifikasi identitas untuk menghapus pairing perangkat IoT ini.',
    );

    if (!authorized || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xff0D1F3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.link_off_rounded, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text('Putuskan Perangkat', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Text(
            'Apakah Anda yakin ingin memutuskan Smart Meter (${DeviceService.deviceIdNotifier.value})?\n\nAliran sensor akan dihentikan dan status koneksi akan dinonaktifkan.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text('Putuskan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      SensorStreamService.instance.stopStreaming();
      await DeviceService.clearPairedDevice();

      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xff0D1F3C),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xff00D9A6)),
                SizedBox(width: 10),
                Text('Pairing perangkat berhasil diputuskan.'),
              ],
            ),
          ),
        );
      }
    }
  }

  void _showPairingExplanation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff0D1F3C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering_rounded, color: Color(0xff00D9A6)),
            SizedBox(width: 10),
            Text('Pairing Tanpa Akun', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cara Kerja Komunikasi:',
              style: TextStyle(color: Color(0xff00D9A6), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text(
              '• ESP32 dan ponsel tidak harus satu jaringan Wi-Fi.\n• ESP32 mengirim data ke Firebase RTDB dengan ID perangkat Anda.\n• Aplikasi membaca data dari ID tersebut secara otomatis.\n• Keamanan fisik relay dan tarif dilindungi oleh PIN lokal di ponsel ini.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff00D9A6)),
            child: const Text('Mengerti', style: TextStyle(color: Color(0xff071426), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
              // SECTION 0: PERANGKAT IOT TERHUBUNG (PAIRING MANDIRI)
              _buildSectionHeader('Perangkat IoT Terhubung (Pairing Mandiri)'),
              ValueListenableBuilder<String>(
                valueListenable: DeviceService.deviceIdNotifier,
                builder: (context, deviceId, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: DeviceService.connectionNotifier,
                    builder: (context, isConnected, _) {
                      return _buildCardContainer([
                        ListTile(
                          leading: const Icon(Icons.router_rounded, color: Color(0xff00D9A6), size: 30),
                          title: Text(
                            'ID Perangkat: $deviceId',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Node RTDB: devices/$deviceId • ${isConnected ? "Terhubung" : "Offline"}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isConnected ? 'Aktif' : 'Offline',
                              style: TextStyle(
                                color: isConnected ? const Color(0xff00D9A6) : Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const Divider(color: Colors.white10),
                        ListTile(
                          leading: const Icon(Icons.sync_alt_rounded, color: Color(0xff00D9A6)),
                          title: const Text('Ganti Kode Pairing Perangkat', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Masukkan ID perangkat ESP32 yang ingin dipantau', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => ConnectDeviceSheet(
                                onConnected: (_) {
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                        const Divider(color: Colors.white10),
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded, color: Color(0xff00D9A6)),
                          title: const Text('Cara Kerja Pairing Mandiri', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Sinkronisasi perangkat tanpa login atau registrasi', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                          onTap: _showPairingExplanation,
                        ),
                        if (isConnected) ...[
                          const Divider(color: Colors.white10),
                          ListTile(
                            leading: const Icon(Icons.link_off_rounded, color: Colors.orangeAccent),
                            title: const Text('Putuskan Perangkat', style: TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                            subtitle: const Text('Hentikan pemantauan telemetri perangkat ini', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.orangeAccent),
                            onTap: _showDisconnectDeviceDialog,
                          ),
                        ],
                      ]);
                    },
                  );
                },
              ),

              const SizedBox(height: 20),

              // SECTION 1: KEAMANAN & OTORISASI
              _buildSectionHeader('Keamanan & Otorisasi Pengguna (Lokal)'),
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