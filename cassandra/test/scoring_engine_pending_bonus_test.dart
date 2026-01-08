import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/features/scoring/scoring_engine.dart';

void main() {
  test('bonus resta 0 finché non sono graded tutte le partite', () {
    final matches = <PredictionMatch>[
      PredictionMatch(
        id: 'm1',
        homeTeam: 'A',
        awayTeam: 'B',
        kickoff: DateTime(2026, 1, 1, 18, 0),
        odds: const Odds(
          home: 2.0,
          draw: 3.0,
          away: 4.0,
          homeDraw: 1.30,
          drawAway: 1.40,
          homeAway: 1.50,
        ),
      ),
      PredictionMatch(
        id: 'm2',
        homeTeam: 'C',
        awayTeam: 'D',
        kickoff: DateTime(2026, 1, 1, 20, 45),
        odds: const Odds(
          home: 1.8,
          draw: 3.4,
          away: 4.2,
          homeDraw: 1.25,
          drawAway: 1.55,
          homeAway: 1.45,
        ),
      ),
    ];

    final picksByMatchId = <String, PickOption>{
      'm1': PickOption.home,
      'm2': PickOption.away,
    };

    // Solo m1 ha outcome: m2 manca => pending implicito
    final partialOutcomes = <String, MatchOutcome>{'m1': MatchOutcome.home};

    final partial = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: partialOutcomes,
    );

    expect(partial.bonusPoints, 0);

    // Ora anche m2 graded: bonus deve applicarsi
    final fullOutcomes = <String, MatchOutcome>{
      'm1': MatchOutcome.home,
      'm2': MatchOutcome.away,
    };

    final full = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: fullOutcomes,
    );

    expect(full.bonusPoints, CassandraScoringEngine.bonusForCorrectCount(2));
  });
}
