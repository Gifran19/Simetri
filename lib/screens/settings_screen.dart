import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/access_approval_service.dart';
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

  // ----------------------------------------------------
  // MANAJEMEN ANGGOTA OLEH PEMILIK (OWNER-ONLY)
  // ----------------------------------------------------
  String _truncateUid(String uid) {
    if (uid.length <= 12) return uid;
    return '${uid.substring(0, 6)}...${uid.substring(uid.length - 4)}';
  }

  Widget _buildOwnerMemberManagementSection(String deviceId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Kelola Izin Anggota (Khusus Pemilik)'),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xff00D9A6), size: 24),
                ),
                title: Row(
                  children: [
                    const Text(
                      'Izin Akses Anggota',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xff00D9A6),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: const Text(
                        'OWNER',
                        style: TextStyle(color: Color(0xff071426), fontSize: 9, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                subtitle: const Text(
                  'Sebagai pemilik, Anda dapat menambah atau mencabut akses anggota keluarga ke perangkat ini.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              const Divider(color: Colors.white10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Anggota Terdaftar',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddMemberDialog(context, deviceId),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xff071426)),
                      label: const Text('Tambah', style: TextStyle(color: Color(0xff071426), fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff00D9A6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<List<DeviceMember>>(
                stream: AccessApprovalService.instance.streamDeviceMembers(deviceId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff00D9A6)),
                        ),
                      ),
                    );
                  }

                  final members = snapshot.data ?? [];
                  if (members.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Belum ada anggota yang didaftarkan. Gunakan tombol "Tambah" di atas untuk membagikan akses ke keluarga via UID.',
                                style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isActive = member.isActive;

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isActive
                              ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                              : Colors.redAccent.withValues(alpha: 0.15),
                          child: Icon(
                            isActive ? Icons.person_rounded : Icons.person_off_rounded,
                            color: isActive ? const Color(0xff00D9A6) : Colors.redAccent,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                member.label.isNotEmpty ? member.label : 'Anggota Keluarga',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                                    : Colors.redAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isActive ? 'Aktif' : 'Dicabut',
                                style: TextStyle(
                                  color: isActive ? const Color(0xff00D9A6) : Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              'UID: ${_truncateUid(member.uid)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white38),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: 'Salin UID',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: member.uid));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('UID anggota disalin ke clipboard.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                          color: const Color(0xff0D1F3C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (value) {
                            if (value == 'revoke') {
                              _confirmRevokeMember(context, deviceId, member);
                            } else if (value == 'activate') {
                              _reactivateMember(context, deviceId, member);
                            } else if (value == 'delete') {
                              _confirmDeleteMember(context, deviceId, member);
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (isActive)
                              const PopupMenuItem(
                                value: 'revoke',
                                child: Row(
                                  children: [
                                    Icon(Icons.block_rounded, color: Colors.orangeAccent, size: 18),
                                    SizedBox(width: 8),
                                    Text('Cabut Akses', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ),
                              )
                            else
                              const PopupMenuItem(
                                value: 'activate',
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle_outline_rounded, color: Color(0xff00D9A6), size: 18),
                                    SizedBox(width: 8),
                                    Text('Aktifkan Kembali', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 8),
                                  Text('Hapus Anggota', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _showAddMemberDialog(BuildContext context, String deviceId) async {
    final uidController = TextEditingController();
    final labelController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xff0D1F3C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: Color(0xff00D9A6)),
                SizedBox(width: 10),
                Text('Tambah Anggota', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Masukkan UID perangkat/ponsel anggota yang ingin diizinkan memantau perangkat ini.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: uidController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'UID Pengguna Anggota *',
                      labelStyle: const TextStyle(color: Color(0xff00D9A6), fontSize: 12),
                      hintText: 'Contoh: AIxw8xBHFUaIrZEC...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xff071426),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, color: Color(0xff00D9A6), size: 18),
                        tooltip: 'Tempel dari Clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.isNotEmpty) {
                            setDialogState(() {
                              uidController.text = data.text!.trim();
                            });
                          }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Label / Nama Anggota (Opsional)',
                      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                      hintText: 'Misal: Kamar Anak / Istri',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xff071426),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Catatan: Anggota dapat melihat UID mereka pada layar Hubungkan Perangkat.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final memberUid = uidController.text.trim();
                        if (memberUid.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('UID Anggota wajib diisi!')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        try {
                          await AccessApprovalService.instance.addOrUpdateMember(
                            deviceId: deviceId,
                            memberUid: memberUid,
                            label: labelController.text.trim(),
                          );

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xff0D1F3C),
                                content: Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Color(0xff00D9A6)),
                                    SizedBox(width: 8),
                                    Text('Izin akses anggota berhasil diberikan!'),
                                  ],
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Gagal memberikan izin: $e')),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff00D9A6)),
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff071426)),
                      )
                    : const Text(
                        'Beri Izin Akses',
                        style: TextStyle(color: Color(0xff071426), fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRevokeMember(BuildContext context, String deviceId, DeviceMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff0D1F3C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Cabut Izin Akses?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Akses anggota "${member.label.isNotEmpty ? member.label : member.uid}" akan dicabut. Pengguna tidak akan dapat memantau atau mengontrol perangkat lagi.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child: const Text('Cabut Akses', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await AccessApprovalService.instance.revokeMember(
          deviceId: deviceId,
          memberUid: member.uid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin akses anggota berhasil dicabut.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mencabut izin: $e')),
          );
        }
      }
    }
  }

  Future<void> _reactivateMember(BuildContext context, String deviceId, DeviceMember member) async {
    try {
      await AccessApprovalService.instance.reactivateMember(
        deviceId: deviceId,
        memberUid: member.uid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin akses anggota diaktifkan kembali.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengaktifkan kembali: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteMember(BuildContext context, String deviceId, DeviceMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff0D1F3C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Hapus Anggota?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Hapus data izin anggota "${member.label.isNotEmpty ? member.label : member.uid}" secara permanen dari perangkat ini?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Hapus Permanen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await AccessApprovalService.instance.removeMember(
          deviceId: deviceId,
          memberUid: member.uid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anggota berhasil dihapus dari perangkat.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus anggota: $e')),
          );
        }
      }
    }
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

              // SECTION KHUSUS OWNER: KELOLA IZIN ANGGOTA
              ValueListenableBuilder<String>(
                valueListenable: DeviceService.deviceIdNotifier,
                builder: (context, deviceId, _) {
                  return StreamBuilder<AccessApprovalResult>(
                    stream: AccessApprovalService.instance.streamDeviceAccess(deviceId),
                    builder: (context, snapshot) {
                      final approval = snapshot.data;
                      // HANYA tampilkan jika role == 'owner' dan status aktif.
                      // Jika pengguna adalah 'member' atau non-owner, pengaturan ini TIDAK DITAMPILKAN.
                      if (approval == null || !approval.isOwner) {
                        return const SizedBox.shrink();
                      }
                      return _buildOwnerMemberManagementSection(deviceId);
                    },
                  );
                },
              ),

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