import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

/// Converte fixtures (API-FOOTBALL) in match pronosticabili.
///
/// Per ora le quote sono mock/deterministiche.
/// Nota importante: di default assegna id "m1..m10" per restare compatibile
/// con i mock e ridurre il rischio di rompere stato interno dei pronostici.
List<PredictionMatch> predictionMatchesFromFixtures(
  List<ApiFootballFixture> fixtures, {
  int take = 10,
  bool useMockIds = true,
}) {
  final sorted = List<ApiFootballFixture>.of(fixtures)
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

  final picked = sorted.take(take).toList();

  return [
    for (var i = 0; i < picked.length; i++)
      predictionMatchFromFixture(
        picked[i],
        idOverride: useMockIds ? 'm${i + 1}' : null,
      ),
  ];
}

/// Converte un singolo fixture in PredictionMatch.
/// Quote: 1 / X / 2 generate deterministicamente.
/// Doppie chance: derivate in modo plausibile da 1/X/2.
PredictionMatch predictionMatchFromFixture(
  ApiFootballFixture f, {
  String? idOverride,
}) {
  final seed = f.fixtureId;

  final home = _odds(seed, 1.35, 3.10); // 1
  final draw = _odds(seed * 7 + 13, 2.70, 4.60); // X
  final away = _odds(seed * 11 + 29, 1.35, 3.40); // 2

  // Probabilità implicite p=1/odds, normalizzate (somma=1)
  final p1 = 1.0 / home;
  final pX = 1.0 / draw;
  final p2 = 1.0 / away;
  final s = p1 + pX + p2;

  double dc(double a, double b) => _round2(s / (a + b));

  // Doppie chance: clamp per mantenerle "plausibili"
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
    id: idOverride ?? 'fx_${f.fixtureId}',
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
  if (max < min) return min;
  if (v < min) return min;
  if (v > max) return max;
  return v;
}
