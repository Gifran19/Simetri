// File: lib/widgets/connect_device_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';

import '../models/device_data.dart';
import '../services/device_service.dart';
import '../services/security_service.dart';
import '../services/sensor_stream_service.dart';

/// Modal Bottom Sheet untuk menghubungkan/pairing aplikasi SIMETRI ke perangkat ESP32
/// melalui Kode Perangkat / Device ID unik tanpa memerlukan akun login.
class ConnectDeviceSheet extends StatefulWidget {
  final Function(DeviceData connectedDevice) onConnected;

  const ConnectDeviceSheet({super.key, required this.onConnected});

  @override
  State<ConnectDeviceSheet> createState() => _ConnectDeviceSheetState();
}

class _ConnectDeviceSheetState extends State<ConnectDeviceSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _deviceCodeController = TextEditingController();

  // Step state: 0 = input pairing code, 1 = connecting, 2 = success
  int _state = 0;
  String _statusMessage = 'Menghubungkan ke ESP32...';
  DeviceData? _connectedDeviceData;

  Timer? _connectTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _deviceCodeController.text = DeviceService.deviceIdNotifier.value;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _deviceCodeController.dispose();
    _connectTimer?.cancel();
    super.dispose();
  }

  void _handleClose() {
    if (_connectedDeviceData != null) {
      widget.onConnected(_connectedDeviceData!);
    }
    Navigator.pop(context);
  }

  Future<void> _startConnection() async {
    final code = _deviceCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xff1A1423),
          content: Text('Kode perangkat tidak boleh kosong!'),
        ),
      );
      return;
    }

    // Simpan Device ID aktif & set target di stream service
    await DeviceService.savePairedDeviceId(code);
    SensorStreamService.instance.setActiveDeviceId(code);

    setState(() {
      _state = 1;
      _statusMessage = 'Menghubungkan ke perangkat ($code)...';
    });

    _connectTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Membaca telemetri sensor PZEM-004T di node devices/$code...';
      });

      _connectTimer = Timer(const Duration(milliseconds: 900), () async {
        if (!mounted) return;

        // Ambil data live dari service dan generate hardware security token
        final secureToken = await SecurityService.getOrGenerateDeviceToken();
        await SecurityService.logSecurityEvent(
          'Pairing IoT',
          'Smart Meter ESP32 ($code) terhubung (Hardware Token: $secureToken)',
        );
        final deviceData = await DeviceService().connectDevice();
        _connectedDeviceData = deviceData;

        // Kirim callback status terhubung
        widget.onConnected(deviceData);

        if (!mounted) return;
        setState(() {
          _statusMessage = 'Sinkronisasi data energi ESP32 berhasil!';
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
                            Icons.sensors_rounded,
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
                                'Pairing Smart Meter ESP32',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Hubungkan ponsel & perangkat via Firebase',
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
              if (_state == 1) _buildConnectingView(),
              if (_state == 2) _buildSuccessView(),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // VIEW: Input Kode Pairing Perangkat ESP32
  // ----------------------------------------------------
  Widget _buildPairingInputView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Edukasi lintas internet
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
              Icon(Icons.wifi_tethering_rounded, color: Color(0xff00D9A6), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ESP32 dan ponsel Anda dapat menggunakan jaringan internet berbeda. Cukup masukkan ID/Kode perangkat yang ingin dipantau.',
                  style: TextStyle(color: Color(0xffB8C2D1), fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Input Kode Perangkat
        const Text(
          'Kode / ID Perangkat ESP32:',
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
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.tag_rounded, color: Color(0xff00D9A6), size: 20),
              ),
              Expanded(
                child: TextField(
                  controller: _deviceCodeController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Misal: simetri_01',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                ),
              ),
              if (_deviceCodeController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                  onPressed: () {
                    setState(() => _deviceCodeController.clear());
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Hint pilihan cepat
        Row(
          children: [
            const Text(
              'Rekomendasi ID: ',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            GestureDetector(
              onTap: () {
                setState(() => _deviceCodeController.text = 'simetri_01');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'simetri_01',
                  style: TextStyle(color: Color(0xff00D9A6), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Tombol Pairing / Hubungkan
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _startConnection,
            icon: const Icon(Icons.link_rounded, size: 20),
            label: const Text(
              'Hubungkan Perangkat Ini',
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
          Text(
            'Perangkat ${_deviceCodeController.text} Terhubung!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aliran data sensor PZEM-004T telah aktif dari Firebase.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
