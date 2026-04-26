import 'meta_prediction_spec.dart';
import 'pick_strategy.dart';
import 'ranking_comparator.dart';
import 'round_lifecycle.dart';
import 'scoring_rules.dart';

enum TournamentKind { league, knockout, hybrid }

class TournamentPhase {
  final String label;
  final ScoringRules scoringRules;
  final PickStrategy pickStrategy;
  final RoundLifecycle roundLifecycle;
  final RankingComparator rankingComparator;
  final MetaPredictionSpec? metaPrediction;

  const TournamentPhase({
    required this.label,
    required this.scoringRules,
    required this.pickStrategy,
    required this.roundLifecycle,
    required this.rankingComparator,
    this.metaPrediction,
  });
}

/// API-Football configuration for a tournament.
class TournamentApiConfig {
  final int leagueId;
  final int season;
  final String timezone;

  const TournamentApiConfig({
    required this.leagueId,
    required this.season,
    this.timezone = 'Europe/Rome',
  });
}

class TournamentMode {
  final String id;
  final String displayName;
  final TournamentKind kind;
  final List<TournamentPhase> phases;
  final String? featureFlagKey;
  final TournamentApiConfig? apiConfig;

  const TournamentMode({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.phases,
    this.featureFlagKey,
    this.apiConfig,
  });
}
