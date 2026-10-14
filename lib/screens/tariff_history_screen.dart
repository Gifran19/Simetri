import 'package:flutter/material.dart';
import '../models/payment_models.dart';
import '../services/device_service.dart';
import '../utils/responsive.dart';
import '../widgets/update_tariff_sheet.dart';

class TariffHistoryScreen extends StatefulWidget {
  const TariffHistoryScreen({super.key});

  @override
  State<TariffHistoryScreen> createState() => _TariffHistoryScreenState();
}

class _TariffHistoryScreenState extends State<TariffHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071426),
      appBar: AppBar(
        backgroundColor: const Color(0xff071426),
        elevation: 0,
        title: const Text(
          'Riwayat Perubahan Tarif',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 800,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner Tarif Aktif Saat Ini
                _buildActiveTariffBanner(),
                const SizedBox(height: 22),

                // Judul Bagian Riwayat
                const Text(
                  'Timeline Riwayat Harga',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Daftar Riwayat Perubahan Tarif
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: DeviceService.tariffHistory.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = DeviceService.tariffHistory[index];
                    return _buildTariffHistoryCard(item);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTariffBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xff00D9A6).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff00D9A6).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xff00D9A6),
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Tarif Listrik Aktif',
                      style: TextStyle(
                        color: Color(0xff00D9A6),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      return UpdateTariffSheet(
                        currentTariff: DeviceService.currentTariff,
                        onSave: (newTariff, date, note) {
                          setState(() {
                            DeviceService.updateTariff(newTariff, date, note);
                          });
                        },
                      );
                    },
                  );
                },
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Ubah', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rp ${DeviceService.currentTariff.toInt()} /kWh',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Berlaku sejak: ${DeviceService.tariffActiveDate}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (DeviceService.tariffNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Catatan: ${DeviceService.tariffNote}',
              style: const TextStyle(
                color: Color(0xff9AA7BD),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTariffHistoryCard(TariffHistoryItem item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isActive
              ? const Color(0xff00D9A6).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: item.isActive ? const Color(0xff00D9A6) : Colors.white24,
              shape: BoxShape.circle,
              boxShadow: item.isActive
                  ? [
                      const BoxShadow(
                        color: Color(0xff00D9A6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.date,
                      style: TextStyle(
                        color: item.isActive ? Colors.white : Colors.white60,
                        fontSize: 12,
                        fontWeight: item.isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: item.isActive
                            ? const Color(0xff00D9A6).withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.isActive ? 'Sedang Aktif' : 'Riwayat',
                        style: TextStyle(
                          color: item.isActive
                              ? const Color(0xff00D9A6)
                              : Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Rp ${item.tariff.toInt()} /kWh',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.note,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}