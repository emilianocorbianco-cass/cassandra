import '../models/match_outcome.dart';
import '../../../services/api_football/models/api_football_fixture.dart';

/// Converte lo status + goals di API-Football in un outcome “Cassandra”.
///
/// Regola semplice e robusta:
/// - match FINITO (FT/AET/PEN/WO/AWD) + goals presenti -> home/draw/away
/// - match annullato/posticipato/sospeso -> voided
/// - tutto il resto -> pending
MatchOutcome matchOutcomeFromFixture(ApiFootballFixture f) {
  final s = f.statusShort.trim().toUpperCase();

  // Status “non giocabile / annullato”
  const voidedStatuses = {'CANC'};
  if (voidedStatuses.contains(s)) return MatchOutcome.voided;

  // Status “finale”
  const finishedStatuses = {'FT', 'AET', 'PEN', 'WO', 'AWD'};
  final finished = finishedStatuses.contains(s);

  if (!finished) return MatchOutcome.pending;

  final hg = f.homeGoals;
  final ag = f.awayGoals;

  if (hg == null || ag == null) return MatchOutcome.pending;

  if (hg > ag) return MatchOutcome.home;
  if (hg < ag) return MatchOutcome.away;
  return MatchOutcome.draw;
}

/// Convenience: outcome per matchId (che nel nostro adapter match = fixtureId.toString()).
Map<String, MatchOutcome> outcomesByMatchIdFromFixtures(
  Iterable<ApiFootballFixture> fixtures,
) {
  final out = <String, MatchOutcome>{};
  for (final f in fixtures) {
    out[f.fixtureId.toString()] = matchOutcomeFromFixture(f);
  }
  return out;
}
