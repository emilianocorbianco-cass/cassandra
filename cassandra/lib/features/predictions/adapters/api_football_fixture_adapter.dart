import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';
import 'package:cassandra/services/api_football/models/api_football_odds.dart';

/// Converte fixtures (API-FOOTBALL) in match pronosticabili.
///
/// Se [realOdds] è presente usa le quote reali dal bookmaker; altrimenti
/// genera quote deterministiche (fallback).
/// Nota importante: di default assegna id "m1..m10" per restare compatibile
/// con i mock e ridurre il rischio di rompere stato interno dei pronostici.
List<PredictionMatch> predictionMatchesFromFixtures(
  List<ApiFootballFixture> fixtures, {
  int take = 10,
  bool useMockIds = true,
  int? matchdayNumber,
  Map<int, ApiFootballFixtureOdds>? realOdds,
}) {
  final sorted = List<ApiFootballFixture>.of(fixtures)
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

  final filtered = matchdayNumber == null
      ? null
      : sorted
            .where(
              (f) => _matchdayFromRound(_fixtureRound(f)) == matchdayNumber,
            )
            .toList();

  final pickedSource = (filtered != null && filtered.isNotEmpty)
      ? filtered
      : sorted;

  final picked = pickedSource.take(take).toList();

  return [
    for (var i = 0; i < picked.length; i++)
      predictionMatchFromFixture(
        picked[i],
        idOverride: useMockIds ? 'm${i + 1}' : null,
        realOdds: realOdds?[picked[i].fixtureId],
      ),
  ];
}

/// Converte un singolo fixture in PredictionMatch.
///
/// Se [realOdds] ha quote Match Winner, le usa; altrimenti genera
/// quote deterministiche. Doppie chance: reali se disponibili,
/// altrimenti derivate probabilisticamente dalle singole.
PredictionMatch predictionMatchFromFixture(
  ApiFootballFixture f, {
  String? idOverride,
  ApiFootballFixtureOdds? realOdds,
}) {
  // --- 1/X/2 ---
  late final double home, draw, away;
  if (realOdds != null && realOdds.hasMatchWinner) {
    home = realOdds.home!;
    draw = realOdds.draw!;
    away = realOdds.away!;
  } else {
    // Fallback: quote deterministiche
    final seed = f.fixtureId;
    home = _odds(seed, 1.35, 3.10);
    draw = _odds(seed * 7 + 13, 2.70, 4.60);
    away = _odds(seed * 11 + 29, 1.35, 3.40);
  }

  // --- Doppie chance ---
  late final double homeDraw, drawAway, homeAway;
  if (realOdds != null && realOdds.hasDoubleChance) {
    homeDraw = realOdds.homeDraw!;
    drawAway = realOdds.drawAway!;
    homeAway = realOdds.homeAway!;
  } else {
    // Derivate probabilisticamente dalle singole (formula esistente)
    final p1 = 1.0 / home;
    final pX = 1.0 / draw;
    final p2 = 1.0 / away;
    final s = p1 + pX + p2;

    double dc(double a, double b) => _round2(s / (a + b));

    homeDraw = _clamp(
      dc(p1, pX),
      min: 1.05,
      max: _round2(_min(home, draw) - 0.01),
    );
    drawAway = _clamp(
      dc(pX, p2),
      min: 1.05,
      max: _round2(_min(draw, away) - 0.01),
    );
    homeAway = _clamp(
      dc(p1, p2),
      min: 1.05,
      max: _round2(_min(home, away) - 0.01),
    );
  }

  return PredictionMatch(
    id: idOverride ?? f.fixtureId.toString(),
    // Manteniamo kickoff in local per coerenza con i mock (che sono local time).
    kickoff: f.kickoffUtc.toLocal(),
    homeTeam: f.homeName,
    awayTeam: f.awayName,
    homeTeamLogo: f.homeLogo,
    awayTeamLogo: f.awayLogo,
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

// --- Recuperi: parsing matchday dal campo "round" (API-Football) ---
// Usiamo accesso dynamic per essere compatibili con diversi shape del model.
String? _fixtureRound(ApiFootballFixture f) {
  final d = f as dynamic;

  // Prova f.round
  try {
    final r = d.round;
    if (r is String) return r;
  } catch (_) {}

  // Prova f.league?.round
  try {
    final league = d.league;
    final r = league?.round;
    if (r is String) return r;
  } catch (_) {}

  // Prova f.leagueRound
  try {
    final r = d.leagueRound;
    if (r is String) return r;
  } catch (_) {}

  return null;
}

int? _matchdayFromRound(String? round) {
  if (round == null) return null;
  // es: "Regular Season - 20" oppure "... 20"
  final m = RegExp(r'(\d{1,2})\s*$').firstMatch(round);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}
