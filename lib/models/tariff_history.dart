class TariffHistory {
  final double oldTariff;
  final double newTariff;
  final String date;
  final String note;

  const TariffHistory({
    required this.oldTariff,
    required this.newTariff,
    required this.date,
    required this.note,
  });
}
