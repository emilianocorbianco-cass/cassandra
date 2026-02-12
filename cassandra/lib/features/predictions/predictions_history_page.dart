import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

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
      app.ensureMatchdayMatchesLoaded();
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
    final l10n = AppLocalizations.of(context)!;
    final en = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('en');

    final savedDays = app.currentUserPicksByMatchday.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.predHistoryTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.predHistoryInfo),
            ),
          ),
          const SizedBox(height: 8),
          if (savedDays.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.predHistoryEmpty),
              ),
            ),
          ...savedDays.map((dayNumber) {
            final picks = app.picksForCurrentUserForMatchday(dayNumber);

            final cached = app.cachedPredictionMatches ?? <PredictionMatch>[];
            final canUseCached = _canUseCachedFor(cached, picks);

            final MatchdayData md = _mockMatchday(dayNumber);

            final saved = app.savedMatchesForMatchday(dayNumber);
            final canUseSaved = saved != null && _canUseCachedFor(saved, picks);

            final matches = canUseSaved
                ? saved
                : (canUseCached ? cached : md.matches);

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

            final daysLabel = formatMatchdayDays(
              matches.map((m) => m.kickoff),
              english: en,
            );

            final totalMatches = matches.length;
            final gradedCount = matches.where((m) {
              final o = outcomes[m.id] ?? MatchOutcome.pending;
              return !o.isPending;
            }).length;

            final resultsLabel = gradedCount == totalMatches
                ? l10n.groupResultsLabel(gradedCount, totalMatches)
                : l10n.groupResultsLabelPartial(gradedCount, totalMatches);

            final tag = canUseSaved
                ? l10n.predHistoryTagSaved
                : (canUseCached
                      ? l10n.predHistoryTagApi
                      : l10n.predHistoryTagDemo);

            return Card(
              child: ListTile(
                title: Text(l10n.groupMatchdayTitle(dayNumber)),
                subtitle: Text('$daysLabel\n$resultsLabel'),
                trailing: Text(tag),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PredictionsMatchdayPage(
                        matchdayNumber: dayNumber,
                        matches: matches,
                        picksByMatchId: picks,
                        outcomesByMatchId: outcomes,
                        isDemoData: !(canUseSaved || canUseCached),
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
