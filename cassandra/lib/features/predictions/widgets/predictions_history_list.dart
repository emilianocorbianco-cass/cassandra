import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/state/cassandra_scope.dart';
import '../../leaderboards/mock_season_data.dart';
import '../../leaderboards/models/matchday_data.dart';
import '../../scoring/models/match_outcome.dart';
import '../models/formatters.dart';
import '../models/prediction_match.dart';
import '../predictions_matchday_page.dart';

class PredictionsHistoryList extends StatelessWidget {
  const PredictionsHistoryList({
    super.key,
    required this.effectiveMatchdayNumber,
    required this.liveMatches,
    required this.liveOutcomes,
  });

  final int effectiveMatchdayNumber;
  final List<PredictionMatch> liveMatches;
  final Map<String, MatchOutcome> liveOutcomes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();

    final liveMatchday = MatchdayData(
      dayNumber: effectiveMatchdayNumber,
      matches: liveMatches,
      outcomesByMatchId: liveOutcomes,
    );
    final historyDaySet = <int>{
      ...appState.recentMatchesByMatchday.keys,
      ...appState.currentUserPicksByMatchday.keys,
      ...appState.matchesByMatchday.keys,
      ...appState.outcomesByMatchday.keys,
    };
    final historyDays = historyDaySet.toList()..sort((a, b) => b.compareTo(a));
    final nonCurrentHistoryDays = historyDays
        .where((day) => day != effectiveMatchdayNumber)
        .toList(growable: false);
    final demoHistory = mockSeasonMatchdays(
      startDay: 16,
      count: 4,
      demoSeed: appState.demoSeed,
    )..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));

    Widget tileFor(MatchdayData md, {String? tag}) {
      final daysLabel = formatMatchdayDays(
        md.matches.map((m) => m.kickoff),
        english: isEnglish,
      );
      final total = md.matches.length;
      final graded = md.matches.where((m) {
        final o = md.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        return !o.isPending;
      }).length;
      final resultsLabel = graded == total
          ? l10n.groupResultsLabel(graded, total)
          : l10n.groupResultsLabelPartial(graded, total);
      final title = tag == null
          ? l10n.groupMatchdayTitle(md.dayNumber)
          : '${l10n.groupMatchdayTitle(md.dayNumber)} ($tag)';
      final savedMatches = appState.matchesByMatchday[md.dayNumber];
      final matchesEffective = (savedMatches != null && savedMatches.isNotEmpty)
          ? savedMatches
          : md.matches;
      final savedOutcomes = appState.outcomesByMatchday[md.dayNumber];
      final outcomesEffective =
          (savedOutcomes != null && savedOutcomes.isNotEmpty)
          ? savedOutcomes
          : md.outcomesByMatchId;
      final picksEffective = appState.picksForCurrentUserForMatchday(
        md.dayNumber,
      );
      return Card(
        child: ListTile(
          title: Text(title),
          subtitle: Text('$daysLabel\n$resultsLabel'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PredictionsMatchdayPage(
                  matchdayNumber: md.dayNumber,
                  matches: matchesEffective,
                  outcomesByMatchId: outcomesEffective,
                  picksByMatchId: picksEffective,
                ),
              ),
            );
          },
        ),
      );
    }

    final liveTag = appState.cachedPredictionMatchesAreReal
        ? l10n.predictionsTagLive
        : l10n.predictionsTagDemo;
    appState.ensureCurrentUserPicksHistoryLoaded();
    final hasSavedLive = appState.hasSavedPicksForMatchday(
      effectiveMatchdayNumber,
    );
    final liveTagEffective = hasSavedLive ? l10n.predictionsTagSaved : liveTag;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.predictionsHistoryDemoInfo,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        tileFor(liveMatchday, tag: liveTagEffective),
        const SizedBox(height: 12),
        if (nonCurrentHistoryDays.isNotEmpty)
          for (final day in nonCurrentHistoryDays)
            Builder(
              builder: (context) {
                final savedMatches = appState.matchesByMatchday[day];
                final recentMatches = appState.recentMatchesByMatchday[day];
                final matchesEffective =
                    (savedMatches != null && savedMatches.isNotEmpty)
                    ? savedMatches
                    : (recentMatches ?? const <PredictionMatch>[]);
                final savedOutcomes = appState.outcomesByMatchday[day];
                final recentOutcomes = appState.recentOutcomesByMatchday[day];
                final outcomesEffective =
                    (savedOutcomes != null && savedOutcomes.isNotEmpty)
                    ? savedOutcomes
                    : (recentOutcomes ?? const <String, MatchOutcome>{});
                final prog = appState.matchdayProgressFor(day);
                final tag =
                    (prog != null && prog.primaryDone && !prog.finalDone)
                    ? l10n.predictionsTagRecoveries
                    : (appState.hasSavedPicksForMatchday(day)
                          ? l10n.predictionsTagSaved
                          : l10n.predictionsTagLive);
                final md = MatchdayData(
                  dayNumber: day,
                  matches: matchesEffective,
                  outcomesByMatchId: outcomesEffective,
                );
                return tileFor(md, tag: tag);
              },
            ),
        if (nonCurrentHistoryDays.isEmpty)
          for (final md in demoHistory)
            tileFor(
              appState.hasSavedOutcomesForMatchday(md.dayNumber)
                  ? MatchdayData(
                      dayNumber: md.dayNumber,
                      matches: md.matches,
                      outcomesByMatchId: appState.outcomesForMatchday(
                        md.dayNumber,
                      ),
                    )
                  : md,
              tag: appState.hasSavedPicksForMatchday(md.dayNumber)
                  ? l10n.predictionsTagSaved
                  : l10n.predictionsTagDemo,
            ),
      ],
    );
  }
}
