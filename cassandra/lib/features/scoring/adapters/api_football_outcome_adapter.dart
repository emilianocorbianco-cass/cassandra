import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

/// Converte uno specifico fixture API-Football in un MatchOutcome “Cassandra”.
///
/// Regole:
/// - Se la partita è annullata/posticipata/abbandonata ecc. => voided
/// - Se è finita (FT/AET/PEN) e abbiamo i goal => home/draw/away
/// - Altrimenti => pending
MatchOutcome matchOutcomeFromFixture(ApiFootballFixture f) {
  final status = f.statusShort.trim().toUpperCase();

  // Stati che consideriamo "annullati" ai fini punteggio.
  // (API-Football usa codici short; questa lista è volutamente conservativa.)
  const voidedStatuses = <String>{
    'CANC', // canceled
    'PST', // postponed
    'ABD', // abandoned
    'AWD', // awarded
    'WO', // walkover
  };

  if (voidedStatuses.contains(status)) return MatchOutcome.voided;

  // Stati conclusi.
  const finishedStatuses = <String>{
    'FT', // full time
    'AET', // after extra time
    'PEN', // penalties
  };

  if (finishedStatuses.contains(status)) {
    final hg = f.homeGoals;
    final ag = f.awayGoals;

    // Se per qualche motivo mancano i goal, non “inventiamo”:
    // restiamo pending finché non abbiamo un outcome consistente.
    if (hg == null || ag == null) return MatchOutcome.pending;

    if (hg > ag) return MatchOutcome.home;
    if (hg < ag) return MatchOutcome.away;
    return MatchOutcome.draw;
  }

  // Tutto il resto: non definitivo (NS, 1H, HT, 2H, ET, LIVE, ecc.)
  return MatchOutcome.pending;
}

/// Convenience: mappa fixtureId -> outcome, usando lo stesso id che usiamo in PredictionMatch.id
Map<String, MatchOutcome> outcomesByMatchIdFromFixtures(
  List<ApiFootballFixture> fixtures,
) {
  final map = <String, MatchOutcome>{};
  for (final f in fixtures) {
    map[f.fixtureId.toString()] = matchOutcomeFromFixture(f);
  }
  return Map.unmodifiable(map);
}
