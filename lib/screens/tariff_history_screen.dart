import 'package:flutter/material.dart';

import '../models/tariff_history.dart';
import '../services/device_service.dart';
import '../utils/responsive.dart';

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
          "Riwayat Perubahan Tarif",

          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),

          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),

      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 800,

          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                _buildActiveTariffBanner(),

                const SizedBox(height: 24),

                const Text(
                  "Riwayat Perubahan Tarif",

                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                ListView.builder(
                  shrinkWrap: true,

                  physics: const NeverScrollableScrollPhysics(),

                  itemCount: DeviceService.tariffHistory.length,

                  itemBuilder: (context, index) {
                    final item = DeviceService.tariffHistory[index];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),

                      child: _buildTariffHistoryCard(item),
                    );
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

        border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.3)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text("Tarif listrik aktif", style: TextStyle(color: Colors.white70, fontSize: 13)),

          const SizedBox(height: 8),

          Text(
            "Rp ${DeviceService.currentTariff.toInt()} /kWh",

            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 6),

          Text(
            "Aktif sejak ${DeviceService.tariffActiveDate}",

            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),

          if (DeviceService.tariffNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),

              child: Text(
                DeviceService.tariffNote,

                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTariffHistoryCard(TariffHistory item) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: const Color(0xff10233F),

        borderRadius: BorderRadius.circular(16),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              Text(item.date, style: const TextStyle(color: Colors.white70, fontSize: 12)),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),

                decoration: BoxDecoration(
                  color: const Color(0xff00D9A6).withValues(alpha: 0.15),

                  borderRadius: BorderRadius.circular(8),
                ),

                child: const Text(
                  "Perubahan",

                  style: TextStyle(color: Color(0xff00D9A6), fontSize: 10),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            "Rp ${item.oldTariff.toInt()} → Rp ${item.newTariff.toInt()} /kWh",

            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 6),

          Text(item.note, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
