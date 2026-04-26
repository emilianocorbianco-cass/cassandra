import 'scoring_rules.dart';

enum TournamentKind { league, knockout, hybrid }

class TournamentPhase {
  final String label;
  final ScoringRules scoringRules;

  const TournamentPhase({required this.label, required this.scoringRules});
}

class TournamentMode {
  final String id;
  final String displayName;
  final TournamentKind kind;
  final List<TournamentPhase> phases;
  final String? featureFlagKey;

  const TournamentMode({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.phases,
    this.featureFlagKey,
  });
}
