class TariffHistoryItem {
  final String date;
  final double tariff;
  final String note;
  final bool isActive;

  const TariffHistoryItem({
    required this.date,
    required this.tariff,
    required this.note,
    this.isActive = false,
  });
}
