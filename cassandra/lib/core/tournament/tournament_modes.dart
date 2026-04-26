import 'serie_a_scoring_rules.dart';
import 'tournament_mode.dart';

/// Pre-defined tournament configurations.
class TournamentModes {
  TournamentModes._();

  static final serieA = TournamentMode(
    id: 'serie-a-2024-25',
    displayName: 'Serie A',
    kind: TournamentKind.league,
    phases: [
      TournamentPhase(
        label: 'Campionato',
        scoringRules: const SerieAScoringRules(),
      ),
    ],
  );
}
