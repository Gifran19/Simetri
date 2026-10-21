import 'dart:async';
import 'package:flutter/material.dart';

import '../models/device_data.dart';
import '../services/device_service.dart';
import '../services/security_service.dart';

/// Modal Bottom Sheet untuk menghubungkan aplikasi SIMETRI ke perangkat IoT (ESP32)
class ConnectDeviceSheet extends StatefulWidget {
  final Function(DeviceData connectedDevice) onConnected;

  const ConnectDeviceSheet({super.key, required this.onConnected});

  @override
  State<ConnectDeviceSheet> createState() => _ConnectDeviceSheetState();
}

class _ConnectDeviceSheetState extends State<ConnectDeviceSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  // Step state: 0 = searching/discovered, 1 = connecting, 2 = success
  int _state = 0;
  String _statusMessage = 'Mencari perangkat SIMETRI di jaringan...';
  DeviceData? _connectedDeviceData;

  Timer? _connectTimer;

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
    _connectTimer?.cancel();
    super.dispose();
  }

  void _handleClose() {
    if (_connectedDeviceData != null) {
      widget.onConnected(_connectedDeviceData!);
    }
    Navigator.pop(context);
  }

  void _startConnection() {
    setState(() {
      _state = 1;
      _statusMessage = 'Melakukan handshake dengan ESP32 Smart Meter...';
    });

    _connectTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Membaca sensor tegangan & arus (PZEM-004T)...';
      });

      _connectTimer = Timer(const Duration(milliseconds: 1000), () async {
        if (!mounted) return;

        // Ambil data live dari service dan generate hardware security token
        final secureToken = await SecurityService.getOrGenerateDeviceToken();
        await SecurityService.logSecurityEvent(
          'Koneksi IoT',
          'Smart Meter ESP32 terhubung (Hardware Token: $secureToken)',
        );
        final deviceData = await DeviceService().connectDevice();
        _connectedDeviceData = deviceData;

        // SEGERA kirim callback status terhubung agar tidak batal jika dialog ditutup manual
        widget.onConnected(deviceData);

        if (!mounted) return;
        setState(() {
          _statusMessage = 'Sinkronisasi data energi & biaya berhasil!';
          _state = 2;
        });

        _connectTimer = Timer(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          Navigator.pop(context);
        });
      });
    });
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.sensors_rounded,
                          color: Color(0xff00D9A6),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Koneksi Perangkat IoT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Smart Meter ESP32 & PZEM-004T',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: _handleClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Dynamic content based on _state
              if (_state == 0) _buildDeviceFoundView(),
              if (_state == 1) _buildConnectingView(),
              if (_state == 2) _buildSuccessView(),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // VIEW: Perangkat Ditemukan & Siap Terhubung
  // ----------------------------------------------------
  Widget _buildDeviceFoundView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Perangkat Terdeteksi di Jaringan Lokal:',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xff00D9A6).withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff00D9A6).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.router_rounded,
                  color: Color(0xff00D9A6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SIMETRI Smart Meter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'ESP32 • 192.168.1.108 • Sinyal Kuat',
                      style: TextStyle(color: Color(0xff00D9A6), fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _startConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff00D9A6),
                  foregroundColor: const Color(0xff071426),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Hubungkan',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xff071426),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white54, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Setelah terhubung, data voltase, arus, daya, dan konsumsi energi akan disalurkan secara langsung.',
                  style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // VIEW: Proses Sinkronisasi / Connecting
  // ----------------------------------------------------
  Widget _buildConnectingView() {
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
            'Menghubungkan ke ESP32...',
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
  // VIEW: Sukses Terhubung
  // ----------------------------------------------------
  Widget _buildSuccessView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xff00D9A6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xff071426),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Perangkat Berhasil Terhubung!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aliran data sensor PZEM-004T telah aktif.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
