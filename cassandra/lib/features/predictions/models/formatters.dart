String formatOdds(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatKickoff(DateTime dt) {
  return '${twoDigits(dt.day)}/${twoDigits(dt.month)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
}
