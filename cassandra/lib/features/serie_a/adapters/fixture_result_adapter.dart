import '../../../services/api_football/models/api_football_fixture.dart';

/// Ritorna un'etichetta tipo "2-1" se i goal sono presenti, altrimenti "-".
String fixtureScoreLabel(ApiFootballFixture f) {
  final (hg, ag) = _goals(f);
  if (hg == null || ag == null) return '-';
  return '$hg-$ag';
}

/// Ritorna "1" / "X" / "2" se i goal sono presenti, altrimenti "".
String fixtureOutcomeLabel(ApiFootballFixture f) {
  final (hg, ag) = _goals(f);
  if (hg == null || ag == null) return '';
  if (hg > ag) return '1';
  if (hg == ag) return 'X';
  return '2';
}

/// Best-effort: estrai goal home/away supportando i due formati più comuni:
/// - f.goalsHome / f.goalsAway
/// - f.goals.home / f.goals.away
///
/// Se nel tuo model i campi hanno nomi diversi, flutter analyze ci dirà esattamente quali.
/// In quel caso correggiamo _goals() (è l’unico punto).
(int? home, int? away) _goals(ApiFootballFixture f) {
  try {
    // ignore: avoid_dynamic_calls
    final hg = (f as dynamic).goalsHome as int?;
    // ignore: avoid_dynamic_calls
    final ag = (f as dynamic).goalsAway as int?;
    return (hg, ag);
  } catch (_) {
    // prova nested
  }

  try {
    // ignore: avoid_dynamic_calls
    final goals = (f as dynamic).goals;
    // ignore: avoid_dynamic_calls
    final hg = goals.home as int?;
    // ignore: avoid_dynamic_calls
    final ag = goals.away as int?;
    return (hg, ag);
  } catch (_) {
    return (null, null);
  }
}
