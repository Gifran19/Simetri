// File: lib/widgets/connect_device_sheet.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device_data.dart';
import '../services/access_approval_service.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';

/// Modal Bottom Sheet untuk menghubungkan aplikasi SIMETRI ke perangkat ESP32
/// melalui alur Persetujuan Akses Admin Lokal (Firebase Spark Friendly).
/// Tidak memerlukan login/registrasi pengguna dan tidak memerlukan Cloud Functions berbayar.
class ConnectDeviceSheet extends StatefulWidget {
  final Function(DeviceData connectedDevice) onConnected;

  const ConnectDeviceSheet({super.key, required this.onConnected});

  @override
  State<ConnectDeviceSheet> createState() => _ConnectDeviceSheetState();
}

class _ConnectDeviceSheetState extends State<ConnectDeviceSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _deviceIdController = TextEditingController();

  // State: 0 = input & verifikasi, 1 = memeriksa izin ke database, 2 = sukses
  int _state = 0;
  String _statusMessage = 'Memeriksa status izin akses...';
  String? _errorMessage;
  DeviceData? _connectedDeviceData;
  String _targetDeviceId = '';
  String _userAnonymousUid = 'Memuat UID...';
  bool _isEspOnline = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _initAnonymousSessionAndDefaultDevice();
  }

  Future<void> _initAnonymousSessionAndDefaultDevice() async {
    final currentDevId = await DeviceService.getPairedDeviceId();
    if (mounted) {
      _deviceIdController.text = currentDevId.isNotEmpty ? currentDevId : 'SIMETRI_ESP32_001';
    }

    try {
      final user = await AuthService.instance.ensureAnonymousSession();
      if (mounted && user != null) {
        setState(() {
          _userAnonymousUid = user.uid;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _userAnonymousUid = 'Sesi Lokal / Belum Login';
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  void _handleClose() {
    if (_connectedDeviceData != null) {
      widget.onConnected(_connectedDeviceData!);
    }
    Navigator.pop(context);
  }

  void _copyUidToClipboard() {
    if (_userAnonymousUid.isNotEmpty && !_userAnonymousUid.startsWith('Memuat')) {
      Clipboard.setData(ClipboardData(text: _userAnonymousUid));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UID anonim berhasil disalin ke clipboard.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xff00D9A6),
        ),
      );
    }
  }

  Future<void> _verifyAccess() async {
    final targetId = _deviceIdController.text.trim();
    if (targetId.isEmpty) {
      setState(() {
        _errorMessage = 'Device ID wajib diisi.';
      });
      return;
    }

    setState(() {
      _state = 1;
      _errorMessage = null;
      _statusMessage = 'Memeriksa izin akses perangkat ($targetId)...';
      _targetDeviceId = targetId;
    });

    try {
      // 1. Verifikasi izin aktif pada node permissions/$uid/$deviceId
      final result = await AccessApprovalService.instance.verifyDeviceAccess(targetId);

      if (!result.isGranted) {
        if (!mounted) return;
        setState(() {
          _state = 0;
          _errorMessage = result.message;
        });
        return;
      }

      // 2. Izin aktif dikonfirmasi -> Periksa telemetri nyata ESP32
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Izin aktif terverifikasi! Memeriksa telemetri ESP32...';
      });

      bool espOnline = false;
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        const maxStaleMs = 30000;

        final liveSnapshot = await FirebaseDatabase.instance
            .ref('devices/$targetId/live')
            .get()
            .timeout(const Duration(seconds: 3));

        if (liveSnapshot.exists && liveSnapshot.value is Map) {
          final liveMap = liveSnapshot.value as Map;
          final dynamic rawTs = liveMap['server_timestamp'] ?? liveMap['timestamp'];
          int? lastTs;
          if (rawTs is int) {
            lastTs = rawTs;
          } else if (rawTs is num) {
            lastTs = rawTs.toInt();
          }

          if (lastTs != null && (nowMs - lastTs).abs() < maxStaleMs) {
            espOnline = true;
          }
        }
      } catch (dbErr) {
        debugPrint('ConnectDeviceSheet check status warning: $dbErr');
      }

      _isEspOnline = espOnline;

      // 3. Konfigurasi state perangkat
      final deviceData = await DeviceService().connectDevice();
      _connectedDeviceData = deviceData;

      if (!mounted) return;
      setState(() {
        _state = 2;
        _statusMessage = result.message;
      });

      widget.onConnected(deviceData);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 0;
        _errorMessage = 'Terjadi kesalahan sistem: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xff0D1F3C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Color(0xff00D9A6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Persetujuan Akses Perangkat SIMETRI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Persetujuan izin admin lokal tanpa login',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _handleClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Dynamic content based on _state
              if (_state == 0) _buildApprovalInputView(),
              if (_state == 1) _buildVerifyingView(),
              if (_state == 2) _buildSuccessView(),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // VIEW: Tampilan UID & Input Device ID
  // ----------------------------------------------------
  Widget _buildApprovalInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kartu Edukasi Alur Persetujuan Admin
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: Color(0xff00D9A6), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tunjukkan UID anonim ini kepada administrator lokal untuk disetujui pada perangkat Anda. '
                  'Aplikasi hanya menyatakan terhubung setelah izin aktif terverifikasi.',
                  style: TextStyle(color: Color(0xffB8C2D1), fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Tampilan UID Anonim
        const Text(
          'UID Anonim Anda (Berikan ke Admin):',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.fingerprint_rounded, color: Color(0xff00D9A6), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  _userAnonymousUid,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Color(0xff00D9A6), size: 18),
                tooltip: 'Salin UID',
                onPressed: _copyUidToClipboard,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Pesan Error jika ada
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Input Device ID
        const Text(
          'Target Device ID:',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _errorMessage != null ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.memory_rounded, color: Color(0xff00D9A6), size: 20),
              ),
              Expanded(
                child: TextField(
                  controller: _deviceIdController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Misal: SIMETRI_ESP32_001',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                ),
              ),
              if (_deviceIdController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                  onPressed: () {
                    setState(() {
                      _deviceIdController.clear();
                      _errorMessage = null;
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tombol Periksa Izin Akses
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _verifyAccess,
            icon: const Icon(Icons.verified_user_rounded, size: 20),
            label: const Text(
              'Periksa & Verifikasi Izin',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff00D9A6),
              foregroundColor: const Color(0xff071426),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // VIEW: Memverifikasi Status Izin
  // ----------------------------------------------------
  Widget _buildVerifyingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xff00D9A6)),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Memverifikasi Izin Akses...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff00D9A6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // VIEW: Sukses Verifikasi Izin Akses
  // ----------------------------------------------------
  Widget _buildSuccessView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xff00D9A6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xff071426),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Izin Akses Terverifikasi!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Device ID: $_targetDeviceId',
            style: const TextStyle(
              color: Color(0xff00D9A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Pembeda status: Izin aktif vs Status Telemetri ESP32
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isEspOnline
                  ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isEspOnline
                    ? const Color(0xff00D9A6).withValues(alpha: 0.4)
                    : Colors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isEspOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: _isEspOnline ? const Color(0xff00D9A6) : Colors.amber,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isEspOnline
                        ? 'ESP32 Online & telemetri terbaca secara sah.'
                        : 'ESP32 belum aktif/offline. Menunggu pengiriman data pertama dari perangkat.',
                    style: TextStyle(
                      color: _isEspOnline ? const Color(0xff00D9A6) : Colors.amber,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tombol Selesai
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _handleClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff00D9A6),
                foregroundColor: const Color(0xff071426),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Buka Dasbor', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
