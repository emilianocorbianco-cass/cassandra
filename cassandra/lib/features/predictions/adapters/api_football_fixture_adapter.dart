import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

/// Converte una lista di fixtures (API-FOOTBALL) in match pronosticabili.
///
/// Nota: per ora le quote sono "mock" (generate in modo deterministico dal fixtureId),
/// perché l’integrazione odds la faremo dopo.
/// Le date sono reali (kickoff) e ci serviranno per lock time.
List<PredictionMatch> predictionMatchesFromFixtures(
  List<ApiFootballFixture> fixtures, {
  int take = 10,
}) {
  final sorted = List<ApiFootballFixture>.of(fixtures)
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

  return sorted.take(take).map(predictionMatchFromFixture).toList();
}

/// Converte un singolo fixture in PredictionMatch.
/// Quote: 1 / X / 2 generate deterministicamente (stabili tra run).
/// Doppie chance: derivate da 1/X/2 in modo plausibile (più basse delle singole).
PredictionMatch predictionMatchFromFixture(ApiFootballFixture f) {
  final seed = f.fixtureId;

  final home = _odds(seed, 1.35, 3.10); // 1
  final draw = _odds(seed * 7 + 13, 2.70, 4.60); // X
  final away = _odds(seed * 11 + 29, 1.35, 3.40); // 2

  // Per le doppie chance usiamo una logica “da bookmaker” molto semplice:
  // 1) convertiamo le quote in probabilità implicite (p=1/odds)
  // 2) normalizziamo togliendo il margine (somma=1)
  // 3) calcoliamo odds della doppia chance: 1/(pA + pB)
  final p1 = 1.0 / home;
  final pX = 1.0 / draw;
  final p2 = 1.0 / away;
  final s = p1 + pX + p2;

  double dc(double a, double b) {
    // equivale a: 1 / ((a/s) + (b/s)) = s / (a+b)
    return _round2(s / (a + b));
  }

  // Doppie chance (con clamp “plausibile”):
  // devono essere < della migliore tra le due singole e comunque >= 1.05
  final homeDraw = _clamp(
    dc(p1, pX),
    min: 1.05,
    max: _round2(_min(home, draw) - 0.01),
  );

  final drawAway = _clamp(
    dc(pX, p2),
    min: 1.05,
    max: _round2(_min(draw, away) - 0.01),
  );

  final homeAway = _clamp(
    dc(p1, p2),
    min: 1.05,
    max: _round2(_min(home, away) - 0.01),
  );

  return PredictionMatch(
    id: 'fx_${f.fixtureId}',
    // Manteniamo kickoff in local per coerenza con i mock (che sono local time).
    kickoff: f.kickoffUtc.toLocal(),
    homeTeam: f.homeName,
    awayTeam: f.awayName,
    odds: Odds(
      home: home,
      draw: draw,
      away: away,
      homeDraw: homeDraw,
      drawAway: drawAway,
      homeAway: homeAway,
    ),
  );
}

/// Generatore quote: min..max, deterministico e arrotondato a 2 decimali.
double _odds(int seed, double min, double max) {
  final n = (seed.abs() % 1000) / 1000.0; // 0.000..0.999
  final raw = min + (max - min) * n;
  return _round2(raw);
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

double _min(double a, double b) => a < b ? a : b;

double _clamp(double v, {required double min, required double max}) {
  // Se max < min (non dovrebbe succedere con i nostri range), scegliamo min.
  if (max < min) return min;
  if (v < min) return min;
  if (v > max) return max;
  return v;
}
