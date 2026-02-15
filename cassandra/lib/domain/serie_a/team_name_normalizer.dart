String normalizeSerieATeamName(String rawName) {
  final trimmed = rawName.trim();
  switch (trimmed.toLowerCase()) {
    case 'as roma':
      return 'Roma';
    case 'ac milan':
      return 'Milan';
    default:
      return trimmed;
  }
}
