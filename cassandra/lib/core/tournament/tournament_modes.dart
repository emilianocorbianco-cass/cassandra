import 'serie_a_pick_strategy.dart';
import 'serie_a_ranking_comparator.dart';
import 'serie_a_round_lifecycle.dart';
import 'serie_a_scoring_rules.dart';
import 'tournament_mode.dart';
import 'tournament_ranking_comparator.dart';
import 'world_cup/world_cup_group_pick_strategy.dart';
import 'world_cup/world_cup_group_scoring_rules.dart';
import 'world_cup/world_cup_knockout_pick_strategy.dart';
import 'world_cup/world_cup_knockout_scoring_rules.dart';
import 'world_cup/world_cup_meta_predictions.dart';
import 'world_cup/world_cup_round_lifecycle.dart';

/// Pre-defined tournament configurations.
class TournamentModes {
  TournamentModes._();

  static final serieA = TournamentMode(
    id: 'serie-a-2024-25',
    displayName: 'Serie A',
    kind: TournamentKind.league,
    apiConfig: const TournamentApiConfig(leagueId: 135, season: 2024),
    phases: [
      TournamentPhase(
        label: 'Campionato',
        scoringRules: const SerieAScoringRules(),
        pickStrategy: const SerieAPickStrategy(),
        roundLifecycle: const SerieARoundLifecycle(),
        rankingComparator: const SerieARankingComparator(),
      ),
    ],
  );

  static final worldCup2026 = TournamentMode(
    id: 'world-cup-2026',
    displayName: 'Mondiali 2026',
    kind: TournamentKind.hybrid,
    featureFlagKey: 'enable_world_cup_2026',
    apiConfig: const TournamentApiConfig(leagueId: 1, season: 2026),
    phases: [
      TournamentPhase(
        label: 'Gironi',
        scoringRules: const WorldCupGroupScoringRules(),
        pickStrategy: const WorldCupGroupPickStrategy(),
        roundLifecycle: const WorldCupGroupRoundLifecycle(),
        rankingComparator: const TournamentRankingComparator(),
        metaPrediction: const WorldCupGroupOrderMeta(),
      ),
      TournamentPhase(
        label: 'Eliminazione',
        scoringRules: const WorldCupKnockoutScoringRules(),
        pickStrategy: const WorldCupKnockoutPickStrategy(),
        roundLifecycle: const WorldCupKnockoutRoundLifecycle(),
        rankingComparator: const TournamentRankingComparator(),
        metaPrediction: const WorldCupTop4Meta(),
      ),
    ],
  );
}
