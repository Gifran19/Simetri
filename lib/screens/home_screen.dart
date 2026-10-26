import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'energy_screen.dart';
import '../firebase_options.dart';
import '../models/device_data.dart';
import '../models/sensor_reading.dart';
import '../services/device_service.dart';
import '../services/sensor_stream_service.dart';
import '../services/security_service.dart';
import '../utils/responsive.dart';
import '../widgets/home_header.dart';
import '../widgets/device_status_card.dart';
import '../widgets/tariff_card.dart';
import '../widgets/monitoring_card.dart';
import '../widgets/energy_summary_card.dart';
import '../widgets/daily_energy_chart.dart';
import '../widgets/monthly_energy_chart.dart';
import '../widgets/connect_device_sheet.dart';

class HomeScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateToTab;
  final bool isInsideShell;

  const HomeScreen({
    super.key,
    this.onNavigateToTab,
    this.isInsideShell = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = false;
  bool _devicePower = false;
  DeviceData _device = DeviceData.disconnected();

  StreamSubscription<SensorReading>? _sensorSubscription;
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _initSensorStream();
    _loadSavedConnectionState();
    DeviceService.connectionNotifier.addListener(_onConnectionNotifierChanged);
    DeviceService.deviceIdNotifier.addListener(_onDeviceIdChanged);
  }

  @override
  void dispose() {
    DeviceService.connectionNotifier.removeListener(_onConnectionNotifierChanged);
    DeviceService.deviceIdNotifier.removeListener(_onDeviceIdChanged);
    _sensorSubscription?.cancel();
    SensorStreamService.instance.stopStreaming();
    super.dispose();
  }

  void _onDeviceIdChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onConnectionNotifierChanged() {
    final connected = DeviceService.connectionNotifier.value;
    if (_isConnected != connected && mounted) {
      _loadSavedConnectionState();
    }
  }

  /// Langganan stream data sensor real-time (Firebase RTDB / Intelligent Simulator)
  void _initSensorStream() {
    _sensorSubscription = SensorStreamService.instance.readingStream.listen((reading) {
      if (!mounted) return;
      if (_isConnected && _devicePower) {
        final currentTariff = DeviceService.currentTariff;
        final double dailyCost = reading.dailyEnergyKwh * currentTariff;
        final double monthlyCost = reading.monthlyEnergyKwh * currentTariff;

        // Perbarui data grafik harian (hari ini dinamis mengikuti akumulasi sensor)
        final currentHistory = List<double>.from(
          _device.dailyHistory.isEmpty
              ? [2.1, 3.5, 1.8, 4.2, 3.1, 5.0, 4.5]
              : _device.dailyHistory,
        );
        if (currentHistory.isNotEmpty) {
          currentHistory[currentHistory.length - 1] = reading.dailyEnergyKwh;
        }

        setState(() {
          _device = _device.copyWith(
            voltage: reading.voltage,
            current: reading.current,
            power: reading.power,
            frequency: reading.frequency,
            powerFactor: reading.powerFactor,
            dailyEnergy: reading.dailyEnergyKwh,
            dailyCost: dailyCost,
            monthlyEnergy: reading.monthlyEnergyKwh,
            monthlyCost: monthlyCost,
            isLiveStream: true,
            streamSource: SensorStreamService.instance.streamSourceLabel,
            dailyHistory: currentHistory,
          );
        });
      }
    });
  }

  /// Memuat status koneksi dan power yang tersimpan sebelumnya
  Future<void> _loadSavedConnectionState() async {
    final savedConnected = await DeviceService.isDeviceConnected();
    final savedPower = await DeviceService.getDevicePower();
    final powerLimit = await DeviceService.getPowerLimit();
    final budget = await DeviceService.getMonthlyBudget();

    if (!mounted) return;
    setState(() {
      _isConnected = savedConnected;
      _devicePower = savedPower;
      _device = DeviceService.getDeviceData(
        isConnected: savedConnected,
        isPowerOn: savedPower,
        powerLimitVa: powerLimit,
        monthlyBudgetRp: budget,
      );
    });

    if (savedConnected && savedPower) {
      SensorStreamService.instance.startStreaming();
    }
  }

  void _openConnectSheet() {
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ConnectDeviceSheet(
          onConnected: (connectedData) async {
            await DeviceService.saveConnectionState(true);
            await DeviceService.saveDevicePower(true);
            final powerLimit = await DeviceService.getPowerLimit();
            final budget = await DeviceService.getMonthlyBudget();

            if (!mounted) return;
            setState(() {
              _isConnected = true;
              _devicePower = true;
              _device = DeviceService.getDeviceData(
                isConnected: true,
                isPowerOn: true,
                powerLimitVa: powerLimit,
                monthlyBudgetRp: budget,
              );
            });

            // Mulai streaming sensor begitu terhubung
            SensorStreamService.instance.startStreaming();

            messenger.showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xff0D1F3C),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xff00D9A6), width: 1),
                ),
                content: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xff00D9A6)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Smart Meter ESP32 terhubung! Data sensor PZEM-004T tersalurkan.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          },
        );
      },
    );
  }

  void _showDisconnectDialog() {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xff0D1F3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.router_rounded, color: Color(0xff00D9A6)),
              SizedBox(width: 10),
              Text(
                'Smart Meter Terhubung',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Perangkat saat ini aktif mengirim data sensor tegangan, arus, dan daya.\n\nApakah Anda ingin memutuskan koneksi?',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                final authorized = await SecurityService.requestAuthorization(
                  context: context,
                  actionTitle: 'Putuskan Smart Meter',
                  actionDescription: 'Verifikasi identitas untuk menghapus koneksi perangkat IoT.',
                );
                if (!authorized) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Pemutusan koneksi dibatalkan.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                await DeviceService.saveConnectionState(false);
                await DeviceService.saveDevicePower(false);

                // Hentikan stream sensor
                SensorStreamService.instance.stopStreaming();

                if (!mounted) return;
                setState(() {
                  _isConnected = false;
                  _devicePower = false;
                  _device = DeviceData.disconnected();
                });

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Perangkat diputuskan. Dashboard dalam status offline.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.shade700),
              child: const Text('Putuskan', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void togglePower(bool value) async {
    if (!_isConnected) return;

    final messenger = ScaffoldMessenger.of(context);

    // Keamanan: Minta otorisasi pengguna (Biometrik / PIN)
    final actionTitle = value ? 'Nyalakan Smart Meter' : 'Matikan Smart Meter';
    final actionDesc = value
        ? 'Verifikasi identitas untuk mengaktifkan kembali pemantauan sensor.'
        : 'Verifikasi identitas untuk menonaktifkan pemantauan Smart Meter.';

    final authorized = await SecurityService.requestAuthorization(
      context: context,
      actionTitle: actionTitle,
      actionDescription: actionDesc,
    );

    if (!authorized) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Otorisasi dibatalkan. Status Smart Meter tidak berubah.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await DeviceService.saveDevicePower(value);
    final powerLimit = await DeviceService.getPowerLimit();
    final budget = await DeviceService.getMonthlyBudget();

    // Kirim sinyal kontrol relay fisik ke ESP32 & sesuaikan streaming
    if (value) {
      SensorStreamService.instance.setRelayPower(true);
      SensorStreamService.instance.startStreaming();
    } else {
      SensorStreamService.instance.setRelayPower(false);
      SensorStreamService.instance.pauseStreamingToZero();
    }

    if (!mounted) return;
    setState(() {
      _devicePower = value;
      _device = DeviceService.getDeviceData(
        isConnected: true,
        isPowerOn: value,
        powerLimitVa: powerLimit,
        monthlyBudgetRp: budget,
      );
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xff0D1F3C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: value ? const Color(0xff00D9A6) : Colors.orangeAccent,
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(
              value ? Icons.power_rounded : Icons.power_off_rounded,
              color: value ? const Color(0xff00D9A6) : Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value
                    ? 'Perangkat IoT dinyalakan (ON). Aliran data sensor aktif kembali.'
                    : 'Perangkat IoT dimatikan (OFF). Aliran data sensor dinonaktifkan.',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openPowerLimitPicker() async {
    const capacities = [450, 900, 1300, 2200, 3500, 4400, 5500, 7700];

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
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
                  const SizedBox(height: 16),
                  const Text(
                    'Pilih Daya Terpasang PLN',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Kapasitas ini digunakan sebagai ambang batas alarm kelebihan beban (MCB trip).',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: capacities.map((va) {
                      final isCurrent = va == _device.powerLimitVa;
                      return ChoiceChip(
                        label: Text(
                          '$va VA',
                          style: TextStyle(color: isCurrent ? Colors.black : Colors.white),
                        ),
                        selected: isCurrent,
                        selectedColor: const Color(0xff00D9A6),
                        backgroundColor: const Color(0xff10233F),
                        onSelected: (val) {
                          Navigator.pop(ctx, va);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null && selected != _device.powerLimitVa) {
      await DeviceService.savePowerLimit(selected);
      if (!mounted) return;
      setState(() {
        _device = _device.copyWith(powerLimitVa: selected);
      });
    }
  }

  /// Dialog modal info status stream dan pengujian Firebase
  void _showStreamInfoModal() {
    final isFbReady = DefaultFirebaseOptions.isConfigured;
    final isReceivingFb = SensorStreamService.instance.isReceivingRealFirebase;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                  decoration: const BoxDecoration(
                    color: Color(0xff0D1F3C),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.sensors_rounded, color: Color(0xff00D9A6)),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status Integrasi Sensor',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'PZEM-004T + ESP32 via Firebase RTDB',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Status Info Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xff071426),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isReceivingFb
                                ? const Color(0xff00D9A6)
                                : Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'Sumber Data',
                              SensorStreamService.instance.streamSourceLabel,
                              valueColor: isReceivingFb ? const Color(0xff00D9A6) : Colors.amber,
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            _buildInfoRow(
                              'Konfigurasi Firebase',
                              isFbReady ? 'Sudah Terpasang' : 'Belum Terisi (Dummy Keys)',
                              valueColor: isFbReady ? const Color(0xff00D9A6) : Colors.orangeAccent,
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            _buildInfoRow(
                              'Node RTDB Target',
                              'devices/simetri_01/live',
                              valueColor: Colors.cyanAccent,
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            _buildInfoRow(
                              'Tegangan Saat Ini',
                              '${_device.voltage.toStringAsFixed(1)} V',
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            _buildInfoRow(
                              'Daya Aktif Saat Ini',
                              '${_device.power.toStringAsFixed(1)} W',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Penjelasan Status IoT
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.lightBlueAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ESP32 sedang dikembangkan oleh rekan magang. Simulator sensor aktif otomatis sehingga Anda tetap dapat menguji dashboard, visualizer, dan kalkulasi biaya.',
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Tombol Uji Kirim Data Firebase
                      if (isFbReady)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final success = await SensorStreamService.instance.sendTestPacketToFirebase();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xff0D1F3C),
                                  content: Text(
                                    success
                                        ? 'Data uji berhasil dikirim ke Firebase RTDB!'
                                        : 'Gagal kirim ke Firebase. Periksa koneksi internet / rules.',
                                    style: TextStyle(
                                      color: success ? const Color(0xff00D9A6) : Colors.redAccent,
                                    ),
                                  ),
                                ),
                              );
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.cloud_upload_rounded),
                            label: const Text('Kirim Data Uji ke Firebase'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff00D9A6),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {Color valueColor = Colors.white}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Badge status stream sensor (Realtime indicator)
  Widget _buildStreamStatusBadge() {
    final isRealFb = SensorStreamService.instance.isReceivingRealFirebase;
    final isStreaming = _isConnected && _devicePower;

    return GestureDetector(
      onTap: _showStreamInfoModal,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xff10233F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isStreaming
                ? (isRealFb ? const Color(0xff00D9A6) : Colors.amber.withValues(alpha: 0.6))
                : Colors.white12,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isStreaming
                    ? (isRealFb ? const Color(0xff00D9A6) : Colors.amber)
                    : Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isStreaming
                    ? 'Stream: ${_device.streamSource}'
                    : 'Stream: Sensor Offline (Hubungkan & Aktifkan Meter)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, color: Colors.white70, size: 13),
                  SizedBox(width: 4),
                  Text('Info', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xff071426),
      bottomNavigationBar: widget.isInsideShell ? null : _buildBottomNav(),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 1050,
          padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 14, vertical: isWide ? 20 : 12),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: isWide ? _buildTabletLayout() : _buildMobileLayout(),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MOBILE LAYOUT (Android & iPhone)
  // ==========================================
  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeHeader(),
        const SizedBox(height: 14),

        // Device Status Card dengan tombol "Hubungkan Perangkat"
        DeviceStatusCard(
          connected: _isConnected,
          power: _devicePower,
          deviceId: DeviceService.deviceIdNotifier.value,
          onChanged: togglePower,
          onConnect: _openConnectSheet,
          onDisconnect: _showDisconnectDialog,
        ),
        const SizedBox(height: 10),

        // Indikator status stream sensor (Realtime Telemetri)
        _buildStreamStatusBadge(),
        const SizedBox(height: 4),

        TariffCard(
          tariff: DeviceService.currentTariff,
          activeDate: DeviceService.tariffActiveDate,
          onTariffChanged: (value, date, note) {
            DeviceService.updateTariff(value, date, note);
            setState(() {});
          },
        ),
        const SizedBox(height: 14),

        // ENLARGED MONITORING CARD (Mengenali state isConnected, isPowerOn, Hz, PF, & Batas MCB)
        MonitoringCard(
          voltage: _device.voltage,
          power: _device.power,
          current: _device.current,
          frequency: _device.frequency,
          powerFactor: _device.powerFactor,
          powerLimitVa: _device.powerLimitVa,
          onConfigureLimit: _openPowerLimitPicker,
          isConnected: _isConnected,
          isPowerOn: _devicePower,
        ),
        const SizedBox(height: 18),

        // SUMMARY HARIAN (Kalkulasi dinamis berdasarkan kWh x Tarif)
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Hari Ini',
          valueLeft: _isConnected ? '${_device.dailyEnergy.toStringAsFixed(2)} kWh' : '0 kWh',
          titleRight: 'Total Biaya Hari Ini',
          valueRight: _isConnected ? _currencyFormatter.format(_device.dailyCost) : 'Rp 0',
          badgeLeft: _isConnected
              ? (_devicePower ? '↓ 12% hemat' : 'Meter Standby')
              : 'Belum terhubung',
          badgeRight: _isConnected
              ? (_devicePower ? 'Sesuai estimasi' : 'Data tersimpan')
              : 'Belum ada data',
        ),
        const SizedBox(height: 14),

        DailyEnergyChart(
          data: _isConnected ? _device.dailyHistory : const [],
          isConnected: _isConnected,
        ),
        const SizedBox(height: 18),

        // SUMMARY BULANAN (Kalkulasi dinamis berdasarkan kWh x Tarif)
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Bulan Ini',
          valueLeft: _isConnected ? '${_device.monthlyEnergy.toStringAsFixed(1)} kWh' : '0 kWh',
          titleRight: 'Total Biaya Bulan Ini',
          valueRight: _isConnected ? _currencyFormatter.format(_device.monthlyCost) : 'Rp 0',
          badgeLeft: _isConnected
              ? (_devicePower ? 'Stabil' : 'OFF (Standby)')
              : 'Belum terhubung',
          badgeRight: _isConnected
              ? (_devicePower ? 'Sesuai estimasi' : 'Data tersimpan')
              : 'Belum ada data',
        ),
        const SizedBox(height: 14),

        MonthlyEnergyChart(data: _device.monthlyEnergyHistory),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================
  // TABLET LAYOUT (iPad, Android Tablets)
  // ==========================================
  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeHeader(),
        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Controls & Real-time Gauges
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  DeviceStatusCard(
                    connected: _isConnected,
                    power: _devicePower,
                    deviceId: DeviceService.deviceIdNotifier.value,
                    onChanged: togglePower,
                    onConnect: _openConnectSheet,
                    onDisconnect: _showDisconnectDialog,
                  ),
                  const SizedBox(height: 10),

                  _buildStreamStatusBadge(),
                  const SizedBox(height: 6),

                  TariffCard(
                    tariff: DeviceService.currentTariff,
                    activeDate: DeviceService.tariffActiveDate,
                    onTariffChanged: (value, date, note) {
                      DeviceService.updateTariff(value, date, note);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  MonitoringCard(
                    voltage: _device.voltage,
                    power: _device.power,
                    current: _device.current,
                    frequency: _device.frequency,
                    powerFactor: _device.powerFactor,
                    powerLimitVa: _device.powerLimitVa,
                    onConfigureLimit: _openPowerLimitPicker,
                    isConnected: _isConnected,
                    isPowerOn: _devicePower,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),

            // Right Column: Energy Charts & Analytics
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Hari Ini',
                    valueLeft: _isConnected ? '${_device.dailyEnergy.toStringAsFixed(2)} kWh' : '0 kWh',
                    titleRight: 'Total Biaya Hari Ini',
                    valueRight: _isConnected ? _currencyFormatter.format(_device.dailyCost) : 'Rp 0',
                    badgeLeft: _isConnected
                        ? (_devicePower ? '↓ 12% hemat' : 'Meter Standby')
                        : 'Belum terhubung',
                    badgeRight: _isConnected
                        ? (_devicePower ? 'Sesuai estimasi' : 'Data tersimpan')
                        : 'Belum ada data',
                  ),
                  const SizedBox(height: 16),

                  DailyEnergyChart(
                    data: _isConnected ? _device.dailyHistory : const [],
                    isConnected: _isConnected,
                  ),
                  const SizedBox(height: 16),

                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Bulan Ini',
                    valueLeft: _isConnected ? '${_device.monthlyEnergy.toStringAsFixed(1)} kWh' : '0 kWh',
                    titleRight: 'Total Biaya Bulan Ini',
                    valueRight: _isConnected ? _currencyFormatter.format(_device.monthlyCost) : 'Rp 0',
                    badgeLeft: _isConnected
                        ? (_devicePower ? 'Stabil' : 'OFF (Standby)')
                        : 'Belum terhubung',
                    badgeRight: _isConnected
                        ? (_devicePower ? 'Sesuai estimasi' : 'Data tersimpan')
                        : 'Belum ada data',
                  ),
                  const SizedBox(height: 16),

                  MonthlyEnergyChart(data: _device.monthlyEnergyHistory),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
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
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Home Icon (Active)
              IconButton(
                icon: const Icon(Icons.home_rounded, color: Color(0xffffc400), size: 28),
                onPressed: () {},
              ),
              // Energy Icon
              IconButton(
                icon: const Icon(Icons.bolt_rounded, color: Colors.white54, size: 28),
                onPressed: () {
                  if (widget.onNavigateToTab != null) {
                    widget.onNavigateToTab!(1);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const EnergyScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
