/// Feature flags for tournament support.
///
/// All flags default to false in production. Serie A is always enabled.
/// Flags are per-tournament: one per format (World Cup, Champions, etc.).
///
/// Currently a shell — will be wired to Firebase Remote Config in Session 3.
class FeatureFlags {
  FeatureFlags._();

  /// Serie A is always enabled (no remote toggle).
  static const bool serieA = true;
}
