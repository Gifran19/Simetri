import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/security_service.dart';

typedef TariffSaveCallback = void Function(
  double tariff,
  DateTime effectiveDate,
  String dateLabel,
  String note,
);

class UpdateTariffSheet extends StatefulWidget {
  final double currentTariff;
  final TariffSaveCallback onSave;

  const UpdateTariffSheet({super.key, required this.currentTariff, required this.onSave});

  @override
  State<UpdateTariffSheet> createState() => _UpdateTariffSheetState();
}

class _UpdateTariffSheetState extends State<UpdateTariffSheet> {
  final TextEditingController _tariffController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  DateTime _effectiveDate = DateTime.now();
  String _selectedOption = 'today';
  String _selectedDateLabel = 'Hari ini';

  @override
  void initState() {
    super.initState();
    _tariffController.text = widget.currentTariff.toInt().toString();
    final now = DateTime.now();
    _effectiveDate = DateTime(now.year, now.month, now.day);
  }

  void _selectPresetDate(String option) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedOption = option;
      if (option == 'today') {
        _effectiveDate = today;
        _selectedDateLabel = 'Hari ini';
      } else if (option == 'tomorrow') {
        _effectiveDate = today.add(const Duration(days: 1));
        _selectedDateLabel = 'Besok (${DateFormat('dd MMMM yyyy').format(_effectiveDate)})';
      } else if (option == 'month') {
        _effectiveDate = DateTime(today.year, today.month + 1, 1);
        _selectedDateLabel = 'Awal Bulan Depan (${DateFormat('dd MMMM yyyy').format(_effectiveDate)})';
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate.isBefore(today) ? today : _effectiveDate,
      firstDate: today,
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (picked != null) {
      setState(() {
        _selectedOption = 'custom';
        _effectiveDate = DateTime(picked.year, picked.month, picked.day);
        if (_effectiveDate == today) {
          _selectedDateLabel = 'Hari ini';
        } else if (_effectiveDate == today.add(const Duration(days: 1))) {
          _selectedDateLabel = 'Besok (${DateFormat('dd MMMM yyyy').format(_effectiveDate)})';
        } else {
          _selectedDateLabel = DateFormat('dd MMMM yyyy').format(_effectiveDate);
        }
      });
    }
  }

  @override
  void dispose() {
    _tariffController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isFuture = _effectiveDate.isAfter(today);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
          decoration: const BoxDecoration(
            color: Color(0xff071426),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // DRAG HANDLE
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

                // HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: Color(0xff00D9A6), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Update Tarif Listrik',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // INFO TARIF SAAT INI
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff10233F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xff00D9A6), size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Tarif aktif saat ini: Rp ${widget.currentTariff.toInt()} /kWh',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // INPUT TARIF BARU
                const Text(
                  'Tarif Baru per kWh (Rp)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tariffController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Masukkan tarif baru',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixText: 'Rp  ',
                    prefixStyle: const TextStyle(
                      color: Color(0xff00D9A6),
                      fontWeight: FontWeight.bold,
                    ),
                    filled: true,
                    fillColor: const Color(0xff10233F),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xff00D9A6)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // TANGGAL BERLAKU
                const Text('Mulai berlaku', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dateButton('Hari ini', 'today'),
                    const SizedBox(width: 8),
                    _dateButton('Besok', 'tomorrow'),
                    const SizedBox(width: 8),
                    _dateButton('1 Bulan Depan', 'month'),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text('Pilih Tanggal Manual ($_selectedDateLabel)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff00D9A6),
                    side: BorderSide(color: const Color(0xff00D9A6).withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                // CATATAN
                const Text(
                  'Catatan perubahan (opsional)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Misal: Penyesuaian tarif listrik PLN',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xff10233F),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xff00D9A6)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // PREVIEW PERUBAHAN & JADWAL
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xff10233F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFuture
                          ? Colors.amber.withValues(alpha: 0.5)
                          : const Color(0xff00D9A6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ringkasan Perubahan:',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            'Rp ${widget.currentTariff.toInt()}  →  Rp ${_tariffController.text.isEmpty ? "0" : _tariffController.text} /kWh',
                            style: const TextStyle(
                              color: Color(0xff00D9A6),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            isFuture ? Icons.event_available_rounded : Icons.flash_on_rounded,
                            size: 15,
                            color: isFuture ? Colors.amber : const Color(0xff00D9A6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isFuture
                                  ? 'Terjadwal: Mulai $_selectedDateLabel\n(Hari ini tetap berjalan dengan Rp ${widget.currentTariff.toInt()} /kWh)'
                                  : 'Langsung berlaku untuk hari ini',
                              style: TextStyle(
                                color: isFuture ? Colors.amber : const Color(0xff00D9A6),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // PENJELASAN
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isFuture
                              ? 'Catatan: Tarif saat ini tidak akan berubah sampai tanggal jadwal tiba. Begitu tanggal tiba, sistem otomatis mengaktifkan tarif baru.'
                              : 'Catatan: Tarif baru akan diterapkan perangkat untuk menghitung ulang seluruh estimasi biaya periode berjalan (biaya = kWh × tarif). Akumulasi energi fisik (kWh) tidak di-reset.',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // TOMBOL SIMPAN
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final value = double.tryParse(_tariffController.text);
                      if (value != null) {
                        final authorized = await SecurityService.requestAuthorization(
                          context: context,
                          actionTitle: isFuture ? 'Jadwalkan Tarif Listrik' : 'Ubah Tarif Listrik',
                          actionDescription: isFuture
                              ? 'Verifikasi identitas untuk menjadwalkan tarif Rp ${value.toInt()} /kWh mulai $_selectedDateLabel.'
                              : 'Verifikasi identitas untuk mengubah tarif listrik ke Rp ${value.toInt()} /kWh mulai hari ini.',
                        );
                        if (!authorized) return;

                        final cleanDateStr = DateFormat('dd MMMM yyyy').format(_effectiveDate);
                        widget.onSave(value, _effectiveDate, cleanDateStr, _noteController.text);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFuture ? Colors.amber : const Color(0xff00D9A6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      isFuture ? 'Jadwalkan Perubahan Tarif' : 'Simpan Perubahan Tarif',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateButton(String text, String option) {
    final isSelected = _selectedOption == option;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _selectPresetDate(option),
        style: OutlinedButton.styleFrom(
          foregroundColor: isSelected ? const Color(0xff00D9A6) : Colors.white70,
          side: BorderSide(color: isSelected ? const Color(0xff00D9A6) : Colors.white24),
          backgroundColor: isSelected
              ? const Color(0xff00D9A6).withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}
