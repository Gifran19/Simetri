import 'package:flutter/material.dart';

import 'update_tariff_sheet.dart';
import '../screens/tariff_history_screen.dart';
import '../services/device_service.dart';
import '../services/live_status.dart';

class TariffCard extends StatelessWidget {
  final double tariff;
  final String activeDate;
  final Function(double, String, String) onTariffChanged;
  final TariffSyncStatus syncStatus;
  final double? appliedTariff;

  const TariffCard({
    super.key,
    required this.tariff,
    required this.activeDate,
    required this.onTariffChanged,
    this.syncStatus = TariffSyncStatus.noData,
    this.appliedTariff,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tarif listrik aktif',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Rp ${tariff.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(
                  text: ' /kWh',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),

          Text(
            'Aktif sejak $activeDate',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),

          // Badge status sinkronisasi Cloud vs Perangkat ESP32
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: syncStatus == TariffSyncStatus.synced
                  ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                  : syncStatus == TariffSyncStatus.deviceOffline
                      ? Colors.orange.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: syncStatus == TariffSyncStatus.synced
                    ? const Color(0xff00D9A6)
                    : syncStatus == TariffSyncStatus.deviceOffline
                        ? Colors.orange
                        : Colors.blue,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  syncStatus == TariffSyncStatus.synced
                      ? Icons.check_circle_outline
                      : syncStatus == TariffSyncStatus.deviceOffline
                          ? Icons.cloud_off_outlined
                          : Icons.sync,
                  size: 13,
                  color: syncStatus == TariffSyncStatus.synced
                      ? const Color(0xff00D9A6)
                      : syncStatus == TariffSyncStatus.deviceOffline
                          ? Colors.orangeAccent
                          : Colors.lightBlueAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  syncStatus.label,
                  style: TextStyle(
                    color: syncStatus == TariffSyncStatus.synced
                        ? const Color(0xff00D9A6)
                        : syncStatus == TariffSyncStatus.deviceOffline
                            ? Colors.orangeAccent
                            : Colors.lightBlueAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) {
                        return UpdateTariffSheet(
                          currentTariff: tariff,
                          onSave: (newTariff, date, note) {
                            onTariffChanged(newTariff, date, note);
                          },
                        );
                      },
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Ubah Tarif',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TariffHistoryScreen()),
                    );
                    onTariffChanged(
                      DeviceService.currentTariff,
                      DeviceService.tariffActiveDate,
                      DeviceService.tariffNote,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Lihat Riwayat',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
