/// Specification for meta-predictions (group order, top 4, etc.).
///
/// Absent for Serie A (null in TournamentPhase).
/// Concrete specs (Champions, World Cup) add their own fields.
abstract class MetaPredictionSpec {
  /// Unique identifier for this spec type.
  String get id;

  /// Display name for the UI.
  String get displayName;
}
