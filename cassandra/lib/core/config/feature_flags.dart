/// Feature flags for tournament support.
///
/// All flags default to false in production. Serie A is always enabled.
/// Flags are per-tournament: one per format (World Cup, Champions, etc.).
class FeatureFlags {
  FeatureFlags._();

  /// Serie A is always enabled (no remote toggle).
  static const bool serieA = true;

  /// Emails of users who can preview the World Cup before the auto-switch date.
  static const List<String> _worldCupTesterEmails = [
    'ecor1982@gmail.com',
    'davidesolinas@icloud.com',
  ];

  /// World Cup 2026 auto-switch window.
  /// Serie A 2025/26 ends ~late May 2026; World Cup starts June 11.
  static final DateTime worldCup2026Start = DateTime(2026, 6, 1);
  static final DateTime worldCup2026End = DateTime(2026, 7, 20);

  /// Whether the World Cup is active based on current date.
  static bool isWorldCup2026Active(DateTime now) {
    return now.isAfter(worldCup2026Start) && now.isBefore(worldCup2026End);
  }

  /// Whether the given user email has tester access to World Cup preview.
  static bool isWorldCupTester(String? email) {
    if (email == null || email.isEmpty) return false;
    return _worldCupTesterEmails.contains(email.toLowerCase().trim());
  }
}
