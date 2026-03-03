String normalizeSerieATeamName(String rawName) {
  final trimmed = rawName.trim();
  switch (trimmed.toLowerCase()) {
    case 'as roma':
      return 'Roma';
    case 'ac milan':
      return 'Milan';
    case 'hellas verona':
    case 'hellas verona fc':
      return 'Verona';
    default:
      return trimmed;
  }
}
