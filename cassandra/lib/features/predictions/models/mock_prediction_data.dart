import 'prediction_match.dart';

List<PredictionMatch> mockPredictionMatches() {
  final now = DateTime.now();

  // Base: tra 2 giorni alle 18:00 (solo per testare facilmente)
  final base = DateTime(
    now.year,
    now.month,
    now.day,
    18,
    0,
  ).add(const Duration(days: 2));

  return [
    PredictionMatch(
      id: 'm1',
      homeTeam: 'Inter',
      awayTeam: 'Milan',
      kickoff: base,
      odds: const Odds(
        home: 2.05,
        draw: 3.40,
        away: 3.60,
        homeDraw: 1.33,
        drawAway: 1.70,
        homeAway: 1.35,
      ),
    ),
    PredictionMatch(
      id: 'm2',
      homeTeam: 'Roma',
      awayTeam: 'Napoli',
      kickoff: base.add(const Duration(hours: 2)),
      odds: const Odds(
        home: 2.75,
        draw: 3.10,
        away: 2.60,
        homeDraw: 1.55,
        drawAway: 1.45,
        homeAway: 1.40,
      ),
    ),
    PredictionMatch(
      id: 'm3',
      homeTeam: 'Juventus',
      awayTeam: 'Lazio',
      kickoff: base.add(const Duration(hours: 4)),
      odds: const Odds(
        home: 1.95,
        draw: 3.30,
        away: 4.10,
        homeDraw: 1.28,
        drawAway: 1.95,
        homeAway: 1.30,
      ),
    ),
    PredictionMatch(
      id: 'm4',
      homeTeam: 'Atalanta',
      awayTeam: 'Fiorentina',
      kickoff: base.add(const Duration(hours: 6)),
      odds: const Odds(
        home: 2.10,
        draw: 3.50,
        away: 3.20,
        homeDraw: 1.35,
        drawAway: 1.65,
        homeAway: 1.38,
      ),
    ),
    PredictionMatch(
      id: 'm5',
      homeTeam: 'Bologna',
      awayTeam: 'Torino',
      kickoff: base.add(const Duration(hours: 24)),
      odds: const Odds(
        home: 2.45,
        draw: 3.05,
        away: 3.05,
        homeDraw: 1.47,
        drawAway: 1.48,
        homeAway: 1.42,
      ),
    ),
    PredictionMatch(
      id: 'm6',
      homeTeam: 'Udinese',
      awayTeam: 'Genoa',
      kickoff: base.add(const Duration(hours: 26)),
      odds: const Odds(
        home: 2.55,
        draw: 3.00,
        away: 2.95,
        homeDraw: 1.52,
        drawAway: 1.50,
        homeAway: 1.44,
      ),
    ),
    PredictionMatch(
      id: 'm7',
      homeTeam: 'Cagliari',
      awayTeam: 'Sassuolo',
      kickoff: base.add(const Duration(hours: 28)),
      odds: const Odds(
        home: 2.80,
        draw: 3.20,
        away: 2.50,
        homeDraw: 1.60,
        drawAway: 1.42,
        homeAway: 1.45,
      ),
    ),
    PredictionMatch(
      id: 'm8',
      homeTeam: 'Verona',
      awayTeam: 'Lecce',
      kickoff: base.add(const Duration(hours: 30)),
      odds: const Odds(
        home: 2.35,
        draw: 3.00,
        away: 3.45,
        homeDraw: 1.43,
        drawAway: 1.62,
        homeAway: 1.40,
      ),
    ),
    PredictionMatch(
      id: 'm9',
      homeTeam: 'Monza',
      awayTeam: 'Empoli',
      kickoff: base.add(const Duration(hours: 32)),
      odds: const Odds(
        home: 2.25,
        draw: 3.15,
        away: 3.25,
        homeDraw: 1.40,
        drawAway: 1.58,
        homeAway: 1.39,
      ),
    ),
    PredictionMatch(
      id: 'm10',
      homeTeam: 'Parma',
      awayTeam: 'Como',
      kickoff: base.add(const Duration(hours: 34)),
      odds: const Odds(
        home: 2.65,
        draw: 3.10,
        away: 2.65,
        homeDraw: 1.55,
        drawAway: 1.55,
        homeAway: 1.45,
      ),
    ),
  ];
}
