String formatOdds(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatKickoff(DateTime dt) {
  return '${twoDigits(dt.day)}/${twoDigits(dt.month)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
}

// --- Helpers IT (poi li renderemo bilingue con intl) ---

const List<String> _itWeekdays = [
  '',
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
];

const List<String> _itMonths = [
  '',
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
];

String italianWeekdayName(int weekday) => _itWeekdays[weekday];
String italianMonthName(int month) => _itMonths[month];

String formatMatchdayDaysItalian(Iterable<DateTime> kickoffs) {
  final days =
      kickoffs.map((dt) => DateTime(dt.year, dt.month, dt.day)).toSet().toList()
        ..sort((a, b) => a.compareTo(b));

  if (days.isEmpty) return '';

  final sameMonth = days.every(
    (d) => d.month == days.first.month && d.year == days.first.year,
  );

  if (sameMonth) {
    final parts = days
        .map((d) => '${italianWeekdayName(d.weekday)} ${d.day}')
        .join(', ');
    return '$parts ${italianMonthName(days.first.month)}';
  } else {
    return days
        .map(
          (d) =>
              '${italianWeekdayName(d.weekday)} ${d.day} ${italianMonthName(d.month)}',
        )
        .join(', ');
  }
}
