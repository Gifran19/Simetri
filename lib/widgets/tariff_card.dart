import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'update_tariff_sheet.dart';
import '../models/scheduled_tariff.dart';
import '../screens/tariff_history_screen.dart';
import '../services/device_service.dart';
import '../services/live_status.dart';

typedef OnTariffChangedCallback = void Function(
  double newTariff,
  DateTime effectiveDate,
  String dateLabel,
  String note,
);

class TariffCard extends StatelessWidget {
  final double tariff;
  final String activeDate;
  final OnTariffChangedCallback onTariffChanged;
  final TariffSyncStatus syncStatus;
  final double? appliedTariff;
  final ScheduledTariff? scheduledTariff;
  final VoidCallback? onCancelScheduled;
  final bool isOwner;

  const TariffCard({
    super.key,
    required this.tariff,
    required this.activeDate,
    required this.onTariffChanged,
    this.syncStatus = TariffSyncStatus.noData,
    this.appliedTariff,
    this.scheduledTariff,
    this.onCancelScheduled,
    this.isOwner = true,
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
            'Aktif sejak ${formatTariffActiveDate(activeDate)}',
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

          // BANNER TARIF TERJADWAL (JIKA ADA)
          if (scheduledTariff != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tarif Baru Terjadwal:',
                          style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Rp ${scheduledTariff!.rate.toInt()} /kWh • ${scheduledTariff!.effectiveDateStr}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (onCancelScheduled != null && isOwner)
                    InkWell(
                      onTap: onCancelScheduled,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Text('Batal', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              if (isOwner)
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
                            onSave: (newTariff, effectiveDate, dateLabel, note) {
                              onTariffChanged(newTariff, effectiveDate, dateLabel, note);
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
                )
              else
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white38),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Tarif (Khusus Owner)',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w500),
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
                      DateTime.now(),
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
                      Icon(Icons.history_rounded, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Riwayat',
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

  /// Menghitung label tanggal aktif secara dinamis relatif terhadap hari ini.
  /// Mencegah teks lama seperti "Besok (05 November 2026)" tetap tertulis ketika hari sudah berganti.
  static String formatTariffActiveDate(String rawDate) {
    if (rawDate.trim().isEmpty) return 'Hari ini';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (rawDate.toLowerCase() == 'hari ini') {
      return 'Hari ini (${DateFormat('dd MMMM yyyy').format(today)})';
    }

    final regex = RegExp(r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})');
    final match = regex.firstMatch(rawDate);

    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final monthStr = match.group(2)!.toLowerCase();
      final year = int.tryParse(match.group(3)!);

      final monthMap = {
        'januari': 1, 'january': 1, 'jan': 1,
        'februari': 2, 'february': 2, 'feb': 2,
        'maret': 3, 'march': 3, 'mar': 3,
        'april': 4, 'apr': 4,
        'mei': 5, 'may': 5,
        'juni': 6, 'june': 6, 'jun': 6,
        'juli': 7, 'july': 7, 'jul': 7,
        'agustus': 8, 'august': 8, 'agu': 8, 'aug': 8,
        'september': 9, 'sep': 9,
        'oktober': 10, 'october': 10, 'okt': 10, 'oct': 10,
        'november': 11, 'nov': 11,
        'desember': 12, 'december': 12, 'des': 12, 'dec': 12,
      };

      final month = monthMap[monthStr];
      if (day != null && month != null && year != null) {
        final targetDate = DateTime(year, month, day);
        final diffDays = targetDate.difference(today).inDays;
        final formattedDate = DateFormat('dd MMMM yyyy').format(targetDate);

        if (diffDays == 0) {
          return 'Hari ini ($formattedDate)';
        } else if (diffDays == -1) {
          return 'Kemarin ($formattedDate)';
        } else if (diffDays == 1) {
          return 'Besok ($formattedDate)';
        } else {
          return formattedDate;
        }
      }
    }

    try {
      final parsed = DateTime.parse(rawDate);
      final targetDate = DateTime(parsed.year, parsed.month, parsed.day);
      final diffDays = targetDate.difference(today).inDays;
      final formattedDate = DateFormat('dd MMMM yyyy').format(targetDate);
      if (diffDays == 0) {
        return 'Hari ini ($formattedDate)';
      } else if (diffDays == -1) {
        return 'Kemarin ($formattedDate)';
      } else if (diffDays == 1) {
        return 'Besok ($formattedDate)';
      } else {
        return formattedDate;
      }
    } catch (_) {}

    return rawDate;
  }
}
