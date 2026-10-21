import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/security_service.dart';

class UpdateTariffSheet extends StatefulWidget {
  final double currentTariff;
  final Function(double tariff, String date, String note) onSave;

  const UpdateTariffSheet({super.key, required this.currentTariff, required this.onSave});

  @override
  State<UpdateTariffSheet> createState() => _UpdateTariffSheetState();
}

class _UpdateTariffSheetState extends State<UpdateTariffSheet> {
  final TextEditingController _tariffController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  String _selectedDate = 'Hari ini';

  @override
  void initState() {
    super.initState();
    // Default isi dengan tarif aktif
    _tariffController.text = widget.currentTariff.toInt().toString();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = DateFormat('dd MMMM yyyy').format(picked);
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    ),
                  ],
                ),
                const Text(
                  'Masukkan nominal tarif listrik per kWh secara manual.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),

                // TARIF SAAT INI
                const Text('Tarif saat ini', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff10233F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    'Rp ${widget.currentTariff.toInt()} /kWh',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // TARIF BARU
                const Text(
                  'Tarif baru (Rp/kWh)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tariffController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Contoh: 1444.70',
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
                    _dateButton('Hari ini'),
                    const SizedBox(width: 8),
                    _dateButton('Besok'),
                    const SizedBox(width: 8),
                    _dateButton('1 Bulan Depan'),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text('Pilih Tanggal Manual ($_selectedDate)'),
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

                // PREVIEW PERUBAHAN
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xff10233F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xff00D9A6).withValues(alpha: 0.2)),
                  ),
                  child: Row(
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
                          actionTitle: 'Ubah Tarif Listrik',
                          actionDescription:
                              'Verifikasi identitas untuk mengubah tarif listrik ke Rp ${value.toInt()} /kWh.',
                        );
                        if (!authorized) return;

                        widget.onSave(value, _selectedDate, _noteController.text);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff00D9A6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Simpan Perubahan Tarif',
                      style: TextStyle(
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

  Widget _dateButton(String text) {
    final isSelected = _selectedDate == text;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _selectedDate = text),
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
