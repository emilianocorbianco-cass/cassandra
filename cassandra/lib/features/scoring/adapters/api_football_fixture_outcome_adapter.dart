import '../../../services/api_football/models/api_football_fixture.dart';
import '../models/match_outcome.dart';

/// Status short che consideriamo “finali” (risultato definitivo).
const Set<String> _finalStatuses = {'FT', 'AET', 'PEN', 'AWD', 'WO'};

bool apiFootballStatusIsFinal(String statusShort) {
  return _finalStatuses.contains(statusShort);
}

/// Ritorna l'outcome solo quando:
/// - statusShort è finale (FT/AET/PEN/...)
/// - homeGoals/awayGoals sono presenti
MatchOutcome? matchOutcomeFromApiFootballFixture(ApiFootballFixture f) {
  if (!apiFootballStatusIsFinal(f.statusShort)) return null;

  final hg = f.homeGoals;
  final ag = f.awayGoals;
  if (hg == null || ag == null) return null;

  if (hg > ag) return MatchOutcome.home;
  if (hg == ag) return MatchOutcome.draw;
  return MatchOutcome.away;
}

Map<String, MatchOutcome> outcomesByMatchIdFromFixtures(
  List<ApiFootballFixture> fixtures,
) {
  final map = <String, MatchOutcome>{};
  for (final f in fixtures) {
    final o = matchOutcomeFromApiFootballFixture(f);
    if (o != null) {
      map[f.fixtureId.toString()] = o;
    }
  }
  return map;
}
