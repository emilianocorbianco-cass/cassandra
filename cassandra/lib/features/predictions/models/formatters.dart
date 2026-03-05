String formatOdds(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatKickoff(DateTime dt) {
  final local = dt.toLocal();
  return '${twoDigits(local.day)}/${twoDigits(local.month)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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

/// Weekday date range: "venerdì 6 marzo - lunedì 9 marzo".
String formatMatchdayWeekdayRange(
  Iterable<DateTime> kickoffs, {
  bool english = false,
}) {
  final days =
      kickoffs
          .map((dt) => dt.toLocal())
          .map((dt) => DateTime(dt.year, dt.month, dt.day))
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b));

  if (days.isEmpty) return '';

  String fmt(DateTime d) =>
      '${_weekdayName(d.weekday, english: english)} ${d.day} ${_monthName(d.month, english: english)}';

  if (days.length == 1) return fmt(days.first);

  return '${fmt(days.first)} - ${fmt(days.last)}';
}

/// Compact date range: "6 marzo - 9 marzo" / "6 March - 9 March".
String formatMatchdayDateRange(
  Iterable<DateTime> kickoffs, {
  bool english = false,
}) {
  final days =
      kickoffs
          .map((dt) => dt.toLocal())
          .map((dt) => DateTime(dt.year, dt.month, dt.day))
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b));

  if (days.isEmpty) return '';
  if (days.length == 1) {
    final d = days.first;
    return '${d.day} ${_monthName(d.month, english: english)}';
  }

  final first = days.first;
  final last = days.last;
  return '${first.day} ${_monthName(first.month, english: english)} - '
      '${last.day} ${_monthName(last.month, english: english)}';
}

/// Retrocompatibile: chiama la versione bilingue con english=false.
String formatMatchdayDaysItalian(Iterable<DateTime> kickoffs) =>
    formatMatchdayDays(kickoffs, english: false);

String formatMatchdayDays(Iterable<DateTime> kickoffs, {bool english = false}) {
  final days =
      kickoffs
          .map((dt) => dt.toLocal())
          .map((dt) => DateTime(dt.year, dt.month, dt.day))
          .toSet()
          .toList()
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
