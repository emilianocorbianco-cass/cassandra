import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../leaderboards/mock_season_data.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import 'predictions_matchday_page.dart';

class PredictionsHistoryPage extends StatefulWidget {
  const PredictionsHistoryPage({super.key});

  @override
  State<PredictionsHistoryPage> createState() => _PredictionsHistoryPageState();
}

class _PredictionsHistoryPageState extends State<PredictionsHistoryPage> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final app = CassandraScope.of(context);

    // Importante: niente notify durante build → post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      app.ensureCurrentUserPicksLoaded();
      app.ensureOutcomesHistoryLoaded();
    });
  }

  MatchdayData _mockMatchday(int dayNumber) {
    return mockSeasonMatchdays(startDay: dayNumber, count: 1).first;
  }

  bool _canUseCachedFor(
    List<PredictionMatch> cachedMatches,
    Map<String, PickOption> picks,
  ) {
    if (cachedMatches.isEmpty || picks.isEmpty) return false;
    final cachedIds = cachedMatches.map((m) => m.id).toSet();
    return picks.keys.every(cachedIds.contains);
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);

    final savedDays = app.currentUserPicksByMatchday.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('Storico pronostici')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Qui trovi le giornate che hai salvato/inviato.\n'
                'Se non abbiamo fixture storiche via API, usiamo un fallback DEMO per mostrare comunque il dettaglio.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (savedDays.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nessuna giornata salvata.\n'
                  'Vai su Pronostici e “invia” almeno una giornata per vederla qui.',
                ),
              ),
            ),
          ...savedDays.map((dayNumber) {
            final picks = app.picksForCurrentUserForMatchday(dayNumber);

            final cached = app.cachedPredictionMatches ?? <PredictionMatch>[];
            final canUseCached = _canUseCachedFor(cached, picks);

            final MatchdayData md = _mockMatchday(dayNumber);
            final matches = canUseCached ? cached : md.matches;

            final outcomes = app.hasSavedOutcomesForMatchday(dayNumber)
                ? app.outcomesForMatchday(dayNumber)
                : (canUseCached
                      ? <String, MatchOutcome>{
                          for (final m in matches)
                            if (app.effectivePredictionOutcomesByMatchId[m
                                    .id] !=
                                null)
                              m.id: app
                                  .effectivePredictionOutcomesByMatchId[m.id]!,
                        }
                      : md.outcomesByMatchId);

            final daysLabel = formatMatchdayDaysItalian(
              matches.map((m) => m.kickoff),
            );

            final totalMatches = matches.length;
            final gradedCount = matches.where((m) {
              final o = outcomes[m.id] ?? MatchOutcome.pending;
              return !o.isPending;
            }).length;

            final resultsLabel = gradedCount == totalMatches
                ? 'risultati: $gradedCount/$totalMatches'
                : 'risultati: $gradedCount/$totalMatches (parziale)';

            return Card(
              child: ListTile(
                title: Text('Giornata $dayNumber'),
                subtitle: Text('$daysLabel\n$resultsLabel'),
                trailing: Text(canUseCached ? 'API' : 'DEMO'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PredictionsMatchdayPage(
                        matchdayNumber: dayNumber,
                        matches: matches,
                        picksByMatchId: picks,
                        outcomesByMatchId: outcomes,
                        isDemoData: !canUseCached,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
