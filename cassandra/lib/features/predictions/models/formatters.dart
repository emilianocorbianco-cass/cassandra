String formatOdds(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatKickoff(DateTime dt) {
  return '${twoDigits(dt.day)}/${twoDigits(dt.month)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
}

// --- Helpers bilingue IT / EN ---

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

const List<String> _enWeekdays = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _enMonths = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String italianWeekdayName(int weekday) => _itWeekdays[weekday];
String italianMonthName(int month) => _itMonths[month];
String englishWeekdayName(int weekday) => _enWeekdays[weekday];
String englishMonthName(int month) => _enMonths[month];

String _weekdayName(int weekday, {required bool english}) =>
    english ? _enWeekdays[weekday] : _itWeekdays[weekday];
String _monthName(int month, {required bool english}) =>
    english ? _enMonths[month] : _itMonths[month];

/// Retrocompatibile: chiama la versione bilingue con english=false.
String formatMatchdayDaysItalian(Iterable<DateTime> kickoffs) =>
    formatMatchdayDays(kickoffs, english: false);

String formatMatchdayDays(Iterable<DateTime> kickoffs, {bool english = false}) {
  final days =
      kickoffs.map((dt) => DateTime(dt.year, dt.month, dt.day)).toSet().toList()
        ..sort((a, b) => a.compareTo(b));

  if (days.isEmpty) return '';

  final sameMonth = days.every(
    (d) => d.month == days.first.month && d.year == days.first.year,
  );

  if (sameMonth) {
    final parts = days
        .map((d) => '${_weekdayName(d.weekday, english: english)} ${d.day}')
        .join(', ');
    return '$parts ${_monthName(days.first.month, english: english)}';
  } else {
    return days
        .map(
          (d) =>
              '${_weekdayName(d.weekday, english: english)} ${d.day} ${_monthName(d.month, english: english)}',
        )
        .join(', ');
  }
}
