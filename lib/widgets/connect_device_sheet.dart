// File: lib/widgets/connect_device_sheet.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/device_data.dart';
import '../services/device_service.dart';
import '../services/pairing_service.dart';
import '../services/sensor_stream_service.dart';

/// Modal Bottom Sheet untuk menghubungkan/pairing aplikasi SIMETRI ke perangkat ESP32
/// menggunakan kode pairing sementara dari backend Cloud Functions.
/// Tidak memerlukan form login atau registrasi akun manual.
class ConnectDeviceSheet extends StatefulWidget {
  final Function(DeviceData connectedDevice) onConnected;

  const ConnectDeviceSheet({super.key, required this.onConnected});

  @override
  State<ConnectDeviceSheet> createState() => _ConnectDeviceSheetState();
}

class _ConnectDeviceSheetState extends State<ConnectDeviceSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _pairingCodeController = TextEditingController();

  // State: 0 = input kode pairing, 1 = memverifikasi ke backend, 2 = sukses
  int _state = 0;
  String _statusMessage = 'Memverifikasi kode pairing...';
  String? _errorMessage;
  DeviceData? _connectedDeviceData;
  String _claimedDeviceId = '';
  bool _isEspOnline = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  void _handleClose() {
    if (_connectedDeviceData != null) {
      widget.onConnected(_connectedDeviceData!);
    }
    Navigator.pop(context);
  }

  Future<void> _startPairing() async {
    final code = _pairingCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Kode pairing wajib diisi.';
      });
      return;
    }

    setState(() {
      _state = 1;
      _errorMessage = null;
      _statusMessage = 'Memverifikasi kode pairing ke server...';
    });

    try {
      // 1. Panggil backend Cloud Function secara aman
      final result = await PairingService.instance.claimDevice(code);

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Kode valid. Mengonfigurasi hak akses perangkat...';
      });

      final deviceId = result.deviceId;
      _claimedDeviceId = deviceId;

      // 2. Simpan Device ID publik (BUKAN kode pairing) ke local storage
      await DeviceService.savePairedDeviceId(deviceId);
      SensorStreamService.instance.setActiveDeviceId(deviceId);

      // 3. Periksa status fisik ESP32 aktual di database
      setState(() {
        _statusMessage = 'Memeriksa status online perangkat ($deviceId)...';
      });

      bool espOnline = false;
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        const maxStaleMs = 30000; // 30 detik toleransi data segar

        // 1. Periksa node live telemetry (server_timestamp aktual yang dikirimkan firmware)
        final liveSnapshot = await FirebaseDatabase.instance
            .ref('devices/$deviceId/live')
            .get();

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

        // 2. Jika live telemetry tidak memenuhi, periksa node status
        // PENTING: Jangan menganggap flag online=true yang sudah lama sebagai bukti online
        if (!espOnline) {
          final statusSnapshot = await FirebaseDatabase.instance
              .ref('devices/$deviceId/status')
              .get();
          if (statusSnapshot.exists && statusSnapshot.value is Map) {
            final val = statusSnapshot.value as Map;
            final isOnlineFlag = val['online'] == true;
            final dynamic rawStatusTs = val['last_seen'] ?? val['updated_at'] ?? val['timestamp'];
            int? statusTs;
            if (rawStatusTs is int) {
              statusTs = rawStatusTs;
            } else if (rawStatusTs is num) {
              statusTs = rawStatusTs.toInt();
            }

            // Hanya anggap online jika flag bernilai true DAN timestamp status masih segar
            if (isOnlineFlag && statusTs != null && (nowMs - statusTs).abs() < maxStaleMs) {
              espOnline = true;
            }
          }
        }
      } catch (dbErr) {
        debugPrint('ConnectDeviceSheet check status warning: $dbErr');
      }

      _isEspOnline = espOnline;

      // 4. Update status koneksi & ambil snapshot model data
      await DeviceService.saveConnectionState(true);
      final deviceData = await DeviceService().connectDevice();
      _connectedDeviceData = deviceData;

      if (!mounted) return;
      setState(() {
        _state = 2;
        _statusMessage = result.message;
      });

      // Panggil callback
      widget.onConnected(deviceData);
    } on PairingException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 0;
        _errorMessage = e.message;
      });
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
                            Icons.security_rounded,
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
                                'Pairing Perangkat SIMETRI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Verifikasi kode pairing aman via backend',
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
              if (_state == 0) _buildPairingInputView(),
              if (_state == 1) _buildVerifyingView(),
              if (_state == 2) _buildSuccessView(),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // VIEW: Input Kode Pairing Sementara
  // ----------------------------------------------------
  Widget _buildPairingInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Edukasi keamanan kode pairing
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
              Icon(Icons.vpn_key_rounded, color: Color(0xff00D9A6), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Masukkan kode pairing sementara yang diterbitkan oleh administrator. Kode ini rahasia, sekali pakai, dan terenkripsi.',
                  style: TextStyle(color: Color(0xffB8C2D1), fontSize: 11, height: 1.4),
                ),
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

        // Input Kode Pairing
        const Text(
          'Kode Pairing Sementara:',
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
                child: Icon(Icons.password_rounded, color: Color(0xff00D9A6), size: 20),
              ),
              Expanded(
                child: TextField(
                  controller: _pairingCodeController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Misal: A3F8B2C1',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 13, letterSpacing: 0),
                  ),
                ),
              ),
              if (_pairingCodeController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                  onPressed: () {
                    setState(() {
                      _pairingCodeController.clear();
                      _errorMessage = null;
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tombol Verifikasi & Hubungkan
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _startPairing,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: const Text(
              'Verifikasi & Hubungkan',
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
  // VIEW: Memverifikasi ke Cloud Functions
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
            'Memproses Otorisasi Backend...',
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
  // VIEW: Sukses Pairing
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
            'Pairing Berhasil!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Device ID: $_claimedDeviceId',
            style: const TextStyle(
              color: Color(0xff00D9A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Pembeda status: Pairing berhasil vs Status ESP32 Online
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
                        ? 'ESP32 Online & mengirim data telemetri.'
                        : 'ESP32 belum aktif/offline. Data akan otomatis masuk saat alat dinyalakan.',
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
