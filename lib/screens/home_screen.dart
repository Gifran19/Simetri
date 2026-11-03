import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../firebase_options.dart';
import '../models/device_data.dart';
import '../models/scheduled_tariff.dart';
import '../models/sensor_reading.dart';
import '../models/yearly_energy_data.dart';
import '../services/access_approval_service.dart';
import '../services/device_service.dart';
import '../services/energy_database_service.dart';
import '../services/live_status.dart';
import '../services/sensor_stream_service.dart';
import '../services/security_service.dart';
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
  bool _isOwner = false;
  DeviceData _device = DeviceData.disconnected();

  // Status kontrol relay & konfirmasi telemetri
  bool _relayPending = false;
  bool _desiredRelay = false;
  DateTime? _baselineTimestamp;
  Timer? _pendingTimer;

  StreamSubscription<SensorReading>? _sensorSubscription;
  StreamSubscription<List<double>>? _weeklySubscription;
  StreamSubscription<YearlyEnergyData>? _yearlySubscription;
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  LiveStatus get _status => SensorStreamService.instance.status;
  SensorReading? get _latestReading => SensorStreamService.instance.latestReading;

  @override
  void initState() {
    super.initState();
    SensorStreamService.instance.statusNotifier.addListener(_onStatusChanged);
    DeviceService.connectionNotifier.addListener(_onConnectionNotifierChanged);
    DeviceService.deviceIdNotifier.addListener(_onDeviceIdChanged);
    DeviceService.initTariff();
    _initSensorStream();
    _initHistoryStreams();
    _loadSavedConnectionState();
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    SensorStreamService.instance.statusNotifier.removeListener(_onStatusChanged);
    DeviceService.connectionNotifier.removeListener(_onConnectionNotifierChanged);
    DeviceService.deviceIdNotifier.removeListener(_onDeviceIdChanged);
    _sensorSubscription?.cancel();
    _weeklySubscription?.cancel();
    _yearlySubscription?.cancel();
    SensorStreamService.instance.stopStreaming();
    super.dispose();
  }

  void _onStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onDeviceIdChanged() {
    _initHistoryStreams();
    if (mounted) {
      setState(() {});
    }
  }

  /// Langganan stream histori mingguan dan tahunan dari Firebase RTDB
  void _initHistoryStreams() {
    _weeklySubscription?.cancel();
    _yearlySubscription?.cancel();

    final dbService = EnergyDatabaseService();
    final now = DateTime.now();

    // Ambil segera snapshot data awal agar tidak menunggu lama
    dbService.fetchWeeklyEnergy().then((weekly) {
      if (mounted && weekly.any((v) => v > 0)) {
        setState(() {
          _device = _device.copyWith(dailyHistory: weekly);
        });
      }
    });

    dbService.fetchYearlyData(now.year).then((yearly) {
      if (mounted && (yearly.monthlyEnergy.any((v) => v > 0) || yearly.totalEnergy > 0)) {
        final curMonthIdx = now.month - 1;
        final curMonthEnergy = yearly.monthlyEnergy.length > curMonthIdx ? yearly.monthlyEnergy[curMonthIdx] : 0.0;
        final curMonthCost = yearly.monthlyCost.length > curMonthIdx ? yearly.monthlyCost[curMonthIdx] : null;

        setState(() {
          _device = _device.copyWith(
            monthlyEnergyHistory: yearly.monthlyEnergy,
            monthlyCostHistory: yearly.monthlyCost,
            monthlyEnergy: curMonthEnergy > _device.monthlyEnergy ? curMonthEnergy : _device.monthlyEnergy,
            monthlyCost: (curMonthCost != null && curMonthCost > (_device.monthlyCost ?? 0)) ? curMonthCost : _device.monthlyCost,
          );
        });
      }
    });

    _weeklySubscription = dbService.streamWeeklyEnergy().listen((weekly) {
      if (mounted) {
        setState(() {
          _device = _device.copyWith(dailyHistory: weekly);
        });
      }
    });

    _yearlySubscription = dbService.streamYearlyData(now.year).listen((yearly) {
      if (mounted) {
        final curMonthIdx = now.month - 1;
        final curMonthEnergy = yearly.monthlyEnergy.length > curMonthIdx ? yearly.monthlyEnergy[curMonthIdx] : 0.0;
        final curMonthCost = yearly.monthlyCost.length > curMonthIdx ? yearly.monthlyCost[curMonthIdx] : null;

        setState(() {
          _device = _device.copyWith(
            monthlyEnergyHistory: yearly.monthlyEnergy,
            monthlyCostHistory: yearly.monthlyCost,
            monthlyEnergy: curMonthEnergy > _device.monthlyEnergy ? curMonthEnergy : _device.monthlyEnergy,
            monthlyCost: (curMonthCost != null && curMonthCost > (_device.monthlyCost ?? 0)) ? curMonthCost : _device.monthlyCost,
          );
        });
      }
    });
  }

  void _onConnectionNotifierChanged() {
    final connected = DeviceService.connectionNotifier.value;
    if (_isConnected != connected && mounted) {
      _loadSavedConnectionState();
    }
  }

  void _clearRelayPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (mounted) {
      setState(() {
        _relayPending = false;
      });
    }
  }

  void _showNotification(String message, {bool isWarning = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xff0D1F3C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isWarning ? Colors.amber : const Color(0xff00D9A6),
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(
              isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
              color: isWarning ? Colors.amber : const Color(0xff00D9A6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Langganan stream data sensor real-time dari Firebase RTDB
  void _initSensorStream() {
    _sensorSubscription = SensorStreamService.instance.readingStream.listen((reading) {
      if (!mounted) return;

      // Konfirmasi perintah relay dari telemetri baru
      if (_relayPending) {
        final confirmState = evaluateRelayConfirmation(
          desired: _desiredRelay,
          baselineTimestamp: _baselineTimestamp,
          latest: reading,
        );

        if (confirmState == RelayCommandState.receivedControlDisabled) {
          _clearRelayPending();
          _showNotification(
            'Perangkat menerima perintah, tetapi kontrol relay dinonaktifkan di firmware (ENABLE_RELAY_CONTROL=false).',
            isWarning: true,
          );
        } else if (confirmState == RelayCommandState.outputReported) {
          _clearRelayPending();
          _showNotification(
            'Perangkat mengonfirmasi status output relay: ${_desiredRelay ? 'ON' : 'OFF'} (sinyal GPIO terkonfirmasi).',
          );
        }
      }

      if (_isConnected) {
        // Biaya: Prioritaskan hasil perhitungan langsung dari ESP32 (reading.dailyCost / monthlyCost).
        // Jika firmware belum menyertakan daily_cost tetapi appliedTariffPerKwh ada, kalikan energi dengan tarif terkonfirmasi.
        // Jika tarif yang diterapkan perangkat belum diketahui, JANGAN gunakan tarif lokal sebagai pengganti diam-diam.
        final double? dailyCost;
        final double? monthlyCost;

        if (reading.dailyCost != null) {
          dailyCost = reading.dailyCost;
          monthlyCost = reading.monthlyCost;
        } else if (reading.appliedTariffPerKwh != null) {
          dailyCost = (reading.dailyEnergyKwh * reading.appliedTariffPerKwh!).roundToDouble();
          monthlyCost = (reading.monthlyEnergyKwh * reading.appliedTariffPerKwh!).roundToDouble();
        } else {
          dailyCost = null;
          monthlyCost = null;
        }

        // Rekonsiliasi pemakaian bulanan:
        // Gunakan akumulasi historis kalender bulanan jika lebih lengkap daripada pembacaan RAM sementara ESP32
        final curMonthIdx = DateTime.now().month - 1;
        final historyMonthlyEnergy = _device.monthlyEnergyHistory.length > curMonthIdx
            ? _device.monthlyEnergyHistory[curMonthIdx]
            : 0.0;
        final historyMonthlyCost = _device.monthlyCostHistory.length > curMonthIdx
            ? _device.monthlyCostHistory[curMonthIdx]
            : null;

        final effectiveMonthlyEnergy = historyMonthlyEnergy > reading.monthlyEnergyKwh
            ? historyMonthlyEnergy
            : reading.monthlyEnergyKwh;
        final effectiveMonthlyCost = (historyMonthlyCost != null && historyMonthlyCost > (monthlyCost ?? 0.0))
            ? historyMonthlyCost
            : monthlyCost;

        setState(() {
          _device = _device.copyWith(
            voltage: reading.voltage,
            current: reading.current,
            power: reading.power,
            frequency: reading.frequency,
            powerFactor: reading.powerFactor,
            dailyEnergy: reading.dailyEnergyKwh,
            dailyCost: dailyCost,
            resetDailyCost: dailyCost == null,
            monthlyEnergy: effectiveMonthlyEnergy,
            monthlyCost: effectiveMonthlyCost,
            resetMonthlyCost: effectiveMonthlyCost == null,
            isLiveStream: reading.isFromFirebase,
            streamSource: SensorStreamService.instance.sourceLabel,
            isSensorValid: reading.isValid,
            isSensorStale: reading.isStale,
            sensorStatusMessage: reading.sensorError,
          );
        });
      }
    });
  }

  /// Memuat status koneksi yang tersimpan sebelumnya
  Future<void> _loadSavedConnectionState() async {
    final savedConnected = await DeviceService.isDeviceConnected();
    final explicitlyDisconnected = await DeviceService.isExplicitlyDisconnected();
    final savedRole = await DeviceService.getUserRole();
    final powerLimit = await DeviceService.getPowerLimit();
    final budget = await DeviceService.getMonthlyBudget();

    if (!mounted) return;
    final prevDaily = _device.dailyHistory;
    final prevMonthlyEnergy = _device.monthlyEnergyHistory;
    final prevMonthlyCost = _device.monthlyCostHistory;

    setState(() {
      _isConnected = savedConnected;
      _isOwner = savedRole.toLowerCase() == 'owner';
      _device = DeviceService.getDeviceData(
        isConnected: savedConnected,
        powerLimitVa: powerLimit,
        monthlyBudgetRp: budget,
      ).copyWith(
        dailyHistory: prevDaily,
        monthlyEnergyHistory: prevMonthlyEnergy,
        monthlyCostHistory: prevMonthlyCost,
      );
    });

    if (savedConnected) {
      SensorStreamService.instance.startStreaming();
      // Verifikasi ulang role di latar belakang agar selalu sinkron
      final pairedId = await DeviceService.getPairedDeviceId();
      AccessApprovalService.instance.verifyDeviceAccess(pairedId).then((approval) {
        if (approval.isGranted && mounted) {
          final isOwner = approval.isOwner;
          DeviceService.saveUserRole(approval.role);
          if (_isOwner != isOwner) {
            setState(() {
              _isOwner = isOwner;
            });
          }
        }
      }).catchError((_) {});
    } else if (!explicitlyDisconnected) {
      // Auto-reconnect HANYA jika pengguna BELUM secara sengaja menekan 'Putuskan'
      final pairedId = await DeviceService.getPairedDeviceId();
      try {
        final approval = await AccessApprovalService.instance.verifyDeviceAccess(pairedId);
        if (approval.isGranted && mounted) {
          await DeviceService.saveConnectionState(true);
          await DeviceService.saveUserRole(approval.role);
          SensorStreamService.instance.startStreaming();
          setState(() {
            _isConnected = true;
            _isOwner = approval.isOwner;
          });
        }
      } catch (_) {}
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
            await DeviceService.setExplicitlyDisconnected(false);
            await DeviceService.saveConnectionState(true);
            final pairedId = await DeviceService.getPairedDeviceId();
            try {
              final approval = await AccessApprovalService.instance.verifyDeviceAccess(pairedId);
              if (approval.isGranted) {
                await DeviceService.saveUserRole(approval.role);
                if (mounted) {
                  setState(() {
                    _isOwner = approval.isOwner;
                  });
                }
              }
            } catch (_) {}
            final powerLimit = await DeviceService.getPowerLimit();
            final budget = await DeviceService.getMonthlyBudget();

            if (!mounted) return;
            final prevDaily = _device.dailyHistory;
            final prevMonthlyEnergy = _device.monthlyEnergyHistory;
            final prevMonthlyCost = _device.monthlyCostHistory;

            setState(() {
              _isConnected = true;
              _device = DeviceService.getDeviceData(
                isConnected: true,
                powerLimitVa: powerLimit,
                monthlyBudgetRp: budget,
              ).copyWith(
                dailyHistory: prevDaily,
                monthlyEnergyHistory: prevMonthlyEnergy,
                monthlyCostHistory: prevMonthlyCost,
              );
            });

            // Mulai streaming sensor begitu terhubung
            SensorStreamService.instance.startStreaming();
            _initHistoryStreams();

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
                        'Smart Meter ESP32 terhubung! Memantau telemetri telemetri nyata.',
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
            'Apakah Anda ingin memutuskan koneksi perangkat Smart Meter ini dari dashboard?',
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

                _clearRelayPending();
                await DeviceService.clearPairedDevice();
                _weeklySubscription?.cancel();
                _yearlySubscription?.cancel();
                SensorStreamService.instance.stopStreaming();

                if (!mounted) return;
                setState(() {
                  _isConnected = false;
                  _isOwner = false;
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

    // Keamanan: Minta otorisasi pengguna (Biometrik / PIN)
    final actionTitle = value ? 'Nyalakan Saklar Relay' : 'Matikan Saklar Relay';
    final actionDesc = value
        ? 'Verifikasi identitas untuk mengirim perintah menyalakan saklar relay.'
        : 'Verifikasi identitas untuk mengirim perintah mematikan saklar relay.';

    final authorized = await SecurityService.requestAuthorization(
      context: context,
      actionTitle: actionTitle,
      actionDescription: actionDesc,
    );

    if (!authorized) {
      _showNotification('Otorisasi dibatalkan. Status saklar tidak berubah.', isWarning: true);
      return;
    }

    if (!_status.deviceReachable) {
      _showNotification('Perangkat sedang offline. Perintah saklar tidak dapat dikirim.', isWarning: true);
      return;
    }

    _desiredRelay = value;
    _baselineTimestamp = _latestReading?.timestamp;

    // Tulis perintah ke Firebase RTDB
    final result = await SensorStreamService.instance.writeRelayCommand(value);

    switch (result) {
      case RelayWriteResult.deviceNotReachable:
        _showNotification('Perangkat tidak terjangkau. Perintah dibatalkan.', isWarning: true);
        return;
      case RelayWriteResult.demoNotSent:
        _showNotification('Mode DEMO: perintah tidak dikirim ke perangkat nyata.', isWarning: true);
        return;
      case RelayWriteResult.firebaseUnavailable:
        _showNotification('Firebase belum siap. Periksa koneksi internet.', isWarning: true);
        return;
      case RelayWriteResult.permissionDenied:
        _showNotification('Izin ditolak oleh server Firebase.', isWarning: true);
        return;
      case RelayWriteResult.timedOut:
        _showNotification('Gagal mengirim perintah: waktu habis.', isWarning: true);
        return;
      case RelayWriteResult.failed:
        _showNotification('Gagal mengirim perintah ke server.', isWarning: true);
        return;
      case RelayWriteResult.written:
        setState(() {
          _relayPending = true;
        });

        // Pasang timeout 20 detik untuk konfirmasi telemetri
        _pendingTimer?.cancel();
        _pendingTimer = Timer(kRelayConfirmTimeout, () {
          if (_relayPending && mounted) {
            _clearRelayPending();
            _showNotification(
              'Batas waktu konfirmasi habis (20 detik). Perangkat belum melaporkan perubahan status relay.',
              isWarning: true,
            );
          }
        });

        _showNotification('Perintah terkirim ke server. Menunggu konfirmasi telemetri perangkat...');
        break;
    }
  }

  Future<void> _handleTariffChanged(
    double value,
    DateTime effectiveDate,
    String date,
    String note,
  ) async {
    if (!_isOwner) {
      _showNotification('Hanya Owner perangkat yang berhak mengubah tarif listrik.', isWarning: true);
      return;
    }
    final result = await DeviceService.updateTariffAsync(
      value,
      date,
      note,
      effectiveDate: effectiveDate,
    );
    if (!mounted) return;
    setState(() {});

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final effectiveStart = DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);
    final isScheduled = effectiveStart.isAfter(todayStart);

    switch (result) {
      case TariffWriteResult.written:
        if (isScheduled) {
          _showNotification('Tarif Rp ${value.toInt()}/kWh berhasil dijadwalkan mulai $date.');
        } else {
          final reachable = SensorStreamService.instance.status.deviceReachable;
          if (reachable) {
            _showNotification('Tarif tersimpan di cloud. Menunggu konfirmasi dari perangkat...');
          } else {
            _showNotification('Tarif tersimpan di cloud. Perangkat sedang offline, akan diterapkan saat online.');
          }
        }
        break;
      case TariffWriteResult.demoNotSent:
        _showNotification('Mode DEMO: tarif tidak dikirim ke perangkat nyata.', isWarning: true);
        break;
      case TariffWriteResult.permissionDenied:
        _showNotification('Gagal mengubah tarif: Izin ditolak oleh server Firebase.', isWarning: true);
        break;
      case TariffWriteResult.timedOut:
        _showNotification('Gagal mengirim tarif: batas waktu habis.', isWarning: true);
        break;
      case TariffWriteResult.invalidValue:
        _showNotification('Nilai tarif tidak valid (harus lebih dari Rp 0).', isWarning: true);
        break;
      case TariffWriteResult.firebaseUnavailable:
        _showNotification('Firebase belum siap. Periksa koneksi internet.', isWarning: true);
        break;
      case TariffWriteResult.failed:
        _showNotification('Gagal menyimpan tarif ke cloud.', isWarning: true);
        break;
    }
  }

  Future<void> _handleCancelScheduledTariff() async {
    if (!_isOwner) {
      _showNotification('Hanya Owner perangkat yang berhak membatalkan jadwal tarif.', isWarning: true);
      return;
    }
    final success = await SensorStreamService.instance.cancelScheduledTariff();
    if (!mounted) return;
    if (success) {
      _showNotification('Jadwal perubahan tarif berhasil dibatalkan.');
    }
  }

  Future<void> _openPowerLimitPicker() async {
    if (!_isOwner) {
      _showNotification('Hanya Owner perangkat yang berhak mengubah batas kapasitas daya.', isWarning: true);
      return;
    }
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

  /// Dialog modal info status stream telemetri nyata
  void _showStreamInfoModal() {
    final isFbReady = DefaultFirebaseOptions.isConfigured;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
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
                              'Status Integrasi Telemetri',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Data nyata PZEM-004T + ESP32 via Firebase RTDB',
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
                        color: _status.deviceReachable
                            ? const Color(0xff00D9A6)
                            : Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Sumber Data',
                          SensorStreamService.instance.sourceLabel,
                          valueColor: _status.deviceReachable ? const Color(0xff00D9A6) : Colors.amber,
                        ),
                        const Divider(color: Colors.white12, height: 16),
                        _buildInfoRow(
                          'Status Perangkat',
                          _status.badge,
                          valueColor: _status == LiveStatus.live
                              ? const Color(0xff00D9A6)
                              : (_status == LiveStatus.demo ? Colors.purpleAccent : Colors.amber),
                        ),
                        const Divider(color: Colors.white12, height: 16),
                        _buildInfoRow(
                          'Konfigurasi Firebase',
                          isFbReady ? 'Sudah Terpasang' : 'Belum Dikonfigurasi',
                          valueColor: isFbReady ? const Color(0xff00D9A6) : Colors.orangeAccent,
                        ),
                        const Divider(color: Colors.white12, height: 16),
                        _buildInfoRow(
                          'Node RTDB Target',
                          SensorStreamService.instance.rtdbLivePath,
                          valueColor: Colors.cyanAccent,
                        ),
                        const Divider(color: Colors.white12, height: 16),
                        _buildInfoRow(
                          'Keterangan',
                          _status.description,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Penjelasan Mode Pemantauan
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.lightBlueAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            kDemoMode
                                ? 'Aplikasi berjalan dalam mode DEMO eksplisit. Data yang ditampilkan adalah simulasi.'
                                : 'Mode Pemantauan Nyata aktif. Tidak ada fallback otomatis ke data simulator. Nilai hanya ditampilkan jika telemetri valid diterima dari perangkat.',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
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
    final Color badgeColor;
    switch (_status) {
      case LiveStatus.live:
        badgeColor = const Color(0xff00D9A6);
        break;
      case LiveStatus.demo:
        badgeColor = Colors.purpleAccent;
        break;
      case LiveStatus.sensorStale:
      case LiveStatus.sensorError:
        badgeColor = Colors.orangeAccent;
        break;
      case LiveStatus.offline:
        badgeColor = Colors.amber;
        break;
      case LiveStatus.noData:
        badgeColor = Colors.white38;
        break;
    }

    return GestureDetector(
      onTap: _showStreamInfoModal,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xff10233F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _status.deviceReachable
                ? badgeColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _status.badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Flexible(
              child: Text(
                SensorStreamService.instance.sourceLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071426),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 600) {
                    return _buildTabletLayout();
                  }
                  return _buildMobileLayout();
                },
              ),
            ),
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

        // Device Status Card dengan switch relay & status telemetri nyata
        DeviceStatusCard(
          connected: _isConnected,
          reachable: _status.deviceReachable,
          relayOn: _latestReading?.relayOutputState ?? false,
          relayPending: _relayPending,
          canControl: _isConnected && _status.deviceReachable && !kDemoMode,
          statusLabel: _status.badge,
          relayNote: _relayPending ? 'Menunggu konfirmasi perangkat...' : null,
          deviceId: DeviceService.deviceIdNotifier.value,
          onChanged: togglePower,
          onConnect: _openConnectSheet,
          onDisconnect: _showDisconnectDialog,
        ),
        const SizedBox(height: 10),

        // Indikator status stream sensor (Realtime Telemetri)
        _buildStreamStatusBadge(),
        const SizedBox(height: 4),

        ValueListenableBuilder<ScheduledTariff?>(
          valueListenable: SensorStreamService.instance.scheduledTariffNotifier,
          builder: (context, scheduledTariff, _) {
            return ValueListenableBuilder<TariffSyncStatus>(
              valueListenable: SensorStreamService.instance.tariffSyncNotifier,
              builder: (context, syncStatus, _) {
                return ValueListenableBuilder<double>(
                  valueListenable: DeviceService.tariffNotifier,
                  builder: (context, currentTariff, _) {
                    return TariffCard(
                      tariff: currentTariff,
                      activeDate: DeviceService.tariffActiveDate,
                      syncStatus: syncStatus,
                      appliedTariff: _latestReading?.appliedTariffPerKwh,
                      scheduledTariff: scheduledTariff,
                      onTariffChanged: _handleTariffChanged,
                      onCancelScheduled: _handleCancelScheduledTariff,
                      isOwner: _isOwner,
                    );
                  },
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),

        // ENLARGED MONITORING CARD
        MonitoringCard(
          voltage: _device.voltage,
          power: _device.power,
          current: _device.current,
          frequency: _device.frequency,
          powerFactor: _device.powerFactor,
          powerLimitVa: _device.powerLimitVa,
          onConfigureLimit: _openPowerLimitPicker,
          isConnected: _isConnected,
          status: _status,
        ),
        const SizedBox(height: 18),

        // SUMMARY HARIAN
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Hari Ini',
          valueLeft: _isConnected && _status.showsMeasurements
              ? '${_device.dailyEnergy.toStringAsFixed(3)} kWh'
              : '-- kWh',
          titleRight: 'Total Biaya Hari Ini',
          valueRight: _isConnected && _status.showsMeasurements
              ? (_device.dailyCost != null ? _currencyFormatter.format(_device.dailyCost) : 'Rp --')
              : 'Rp --',
          badgeLeft: _isConnected ? _status.badge : 'Belum terhubung',
          badgeRight: _isConnected
              ? (_latestReading?.appliedTariffPerKwh != null
                  ? 'Tarif Rp ${_latestReading!.appliedTariffPerKwh!.toInt()}/kWh'
                  : 'Tarif belum dikonfirmasi')
              : 'Belum ada data',
        ),
        const SizedBox(height: 14),

        DailyEnergyChart(
          data: _isConnected ? _device.dailyHistory : const [],
          isConnected: _isConnected,
          deviceId: DeviceService.deviceIdNotifier.value,
          liveTodayEnergy: _isConnected ? _device.dailyEnergy : null,
          liveTodayCost: _isConnected ? _device.dailyCost : null,
        ),
        const SizedBox(height: 18),

        // SUMMARY BULANAN
        EnergySummaryCard(
          titleLeft: 'Total Pemakaian Bulan Ini',
          valueLeft: _isConnected && _status.showsMeasurements
              ? '${_device.monthlyEnergy.toStringAsFixed(3)} kWh'
              : '-- kWh',
          titleRight: 'Total Biaya Bulan Ini',
          valueRight: _isConnected && _status.showsMeasurements
              ? (_device.monthlyCost != null ? _currencyFormatter.format(_device.monthlyCost) : 'Rp --')
              : 'Rp --',
          badgeLeft: _isConnected ? _status.badge : 'Belum terhubung',
          badgeRight: _isConnected ? 'Target Anggaran' : 'Belum ada data',
        ),
        const SizedBox(height: 14),

        MonthlyEnergyChart(
          data: _device.monthlyEnergyHistory,
          isConnected: _isConnected,
        ),
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
                    reachable: _status.deviceReachable,
                    relayOn: _latestReading?.relayOutputState ?? false,
                    relayPending: _relayPending,
                    canControl: _isConnected && _status.deviceReachable && !kDemoMode,
                    statusLabel: _status.badge,
                    relayNote: _relayPending ? 'Menunggu konfirmasi perangkat...' : null,
                    deviceId: DeviceService.deviceIdNotifier.value,
                    onChanged: togglePower,
                    onConnect: _openConnectSheet,
                    onDisconnect: _showDisconnectDialog,
                  ),
                  const SizedBox(height: 10),

                  _buildStreamStatusBadge(),
                  const SizedBox(height: 6),

                  ValueListenableBuilder<ScheduledTariff?>(
                    valueListenable: SensorStreamService.instance.scheduledTariffNotifier,
                    builder: (context, scheduledTariff, _) {
                      return ValueListenableBuilder<TariffSyncStatus>(
                        valueListenable: SensorStreamService.instance.tariffSyncNotifier,
                        builder: (context, syncStatus, _) {
                          return ValueListenableBuilder<double>(
                            valueListenable: DeviceService.tariffNotifier,
                            builder: (context, currentTariff, _) {
                              return TariffCard(
                                tariff: currentTariff,
                                activeDate: DeviceService.tariffActiveDate,
                                syncStatus: syncStatus,
                                appliedTariff: _latestReading?.appliedTariffPerKwh,
                                scheduledTariff: scheduledTariff,
                                onTariffChanged: _handleTariffChanged,
                                onCancelScheduled: _handleCancelScheduledTariff,
                                isOwner: _isOwner,
                              );
                            },
                          );
                        },
                      );
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
                    status: _status,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),

            // Right Column: Summary & Analytics Charts
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Hari Ini',
                    valueLeft: _isConnected && _status.showsMeasurements
                        ? '${_device.dailyEnergy.toStringAsFixed(3)} kWh'
                        : '-- kWh',
                    titleRight: 'Total Biaya Hari Ini',
                    valueRight: _isConnected && _status.showsMeasurements
                        ? (_device.dailyCost != null ? _currencyFormatter.format(_device.dailyCost) : 'Rp --')
                        : 'Rp --',
                    badgeLeft: _isConnected ? _status.badge : 'Belum terhubung',
                    badgeRight: _isConnected
                        ? (_latestReading?.appliedTariffPerKwh != null
                            ? 'Tarif Rp ${_latestReading!.appliedTariffPerKwh!.toInt()}/kWh'
                            : 'Tarif belum dikonfirmasi')
                        : 'Belum ada data',
                  ),
                  const SizedBox(height: 16),

                  DailyEnergyChart(
                    data: _isConnected ? _device.dailyHistory : const [],
                    isConnected: _isConnected,
                    deviceId: DeviceService.deviceIdNotifier.value,
                    liveTodayEnergy: _isConnected ? _device.dailyEnergy : null,
                    liveTodayCost: _isConnected ? _device.dailyCost : null,
                  ),
                  const SizedBox(height: 16),

                  EnergySummaryCard(
                    titleLeft: 'Total Pemakaian Bulan Ini',
                    valueLeft: _isConnected && _status.showsMeasurements
                        ? '${_device.monthlyEnergy.toStringAsFixed(3)} kWh'
                        : '-- kWh',
                    titleRight: 'Total Biaya Bulan Ini',
                    valueRight: _isConnected && _status.showsMeasurements
                        ? (_device.monthlyCost != null ? _currencyFormatter.format(_device.monthlyCost) : 'Rp --')
                        : 'Rp --',
                    badgeLeft: _isConnected ? _status.badge : 'Belum terhubung',
                    badgeRight: _isConnected ? 'Target Anggaran' : 'Belum ada data',
                  ),
                  const SizedBox(height: 16),

                  MonthlyEnergyChart(
          data: _device.monthlyEnergyHistory,
          isConnected: _isConnected,
        ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
