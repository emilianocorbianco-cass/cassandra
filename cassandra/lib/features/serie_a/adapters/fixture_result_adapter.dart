import '../../../services/api_football/models/api_football_fixture.dart';

bool fixtureIsFinal(ApiFootballFixture f) {
  // API-Football usa questi status short (tra gli altri).
  // Qui consideriamo "finale" quando il risultato è definitivo.
  const finals = {'FT', 'AET', 'PEN', 'AWD', 'WO'};
  return finals.contains(f.statusShort);
}

/// Ritorna un'etichetta tipo "2-1" se i goal sono presenti, altrimenti "-".
String fixtureScoreLabel(ApiFootballFixture f) {
  final hg = f.homeGoals;
  final ag = f.awayGoals;
  if (hg == null || ag == null) return '-';
  return '$hg-$ag';
}

/// Ritorna "1" / "X" / "2" SOLO se:
/// - i goal sono presenti
/// - lo status indica match concluso (FT/AET/PEN/...)
String fixtureOutcomeLabel(ApiFootballFixture f) {
  final hg = f.homeGoals;
  final ag = f.awayGoals;
  if (hg == null || ag == null) return '';
  if (!fixtureIsFinal(f)) return '';

  if (hg > ag) return '1';
  if (hg == ag) return 'X';
  return '2';
}
