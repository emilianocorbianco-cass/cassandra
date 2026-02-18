import 'package:flutter/material.dart';
import 'dart:async';

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';

import '../../features/chat/chat_page.dart';
import '../../features/settings/settings_page.dart';
import 'package:cassandra/features/serie_a/serie_a_page.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_colors.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show MatchdayProgress, computeMatchdayProgress;
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../services/firestore/models/matchday_document.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Timer? _liveSyncTimer;
  bool _liveSyncInFlight = false;
  bool _didInitialLiveSync = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureLiveSync();
  }

  void _configureLiveSync() {
    final app = CassandraScope.of(context);
    final canSync = app.firestoreService != null && app.isAuthenticated;

    if (!canSync) {
      _liveSyncTimer?.cancel();
      _liveSyncTimer = null;
      _didInitialLiveSync = false;
      return;
    }

    _liveSyncTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncLiveFromBackend()),
    );

    if (!_didInitialLiveSync) {
      _didInitialLiveSync = true;
      unawaited(_syncLiveFromBackend());
    }
  }

  Future<void> _syncLiveFromBackend() async {
    if (!mounted || _liveSyncInFlight) return;

    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    _liveSyncInFlight = true;

    try {
      final standingsFuture = fs.getSeasonStandings(
        seasonKey: app.currentSeasonKey,
      );
      final now = DateTime.now();
      var dayNumber = app.cassandraMatchdayCursor;
      app.ensureOriginKickoffsLoaded();

      MatchdayDocument? resolvedDoc;
      MatchdayProgress? resolvedProgress;

      const maxLookAheadDays = 12;
      for (var i = 0; i <= maxLookAheadDays; i++) {
        final candidate = await fs.getMatchdayData(
          seasonKey: app.currentSeasonKey,
          dayNumber: dayNumber,
        );
        if (candidate == null || candidate.matches.isEmpty) {
          dayNumber += 1;
          continue;
        }

        final matches = candidate.matches;
        final outcomes = candidate.outcomesByMatchId;
        for (final m in matches) {
          app.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
        }

        String statusFor(PredictionMatch m) =>
            (outcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        final progress = computeMatchdayProgress<PredictionMatch>(
          matches,
          now: now,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) =>
              app.originKickoffFor(matchId: m.id, fallbackKickoff: m.kickoff),
          statusShort: (m) => statusFor(m),
        );

        app.setMatchdayProgress(
          matchdayNumber: candidate.dayNumber,
          progress: progress,
          allowAutoAdvance: false,
        );

        resolvedDoc = candidate;
        resolvedProgress = progress;
        if (!progress.primaryDone) break;
        dayNumber += 1;
      }

      await app.persistOriginKickoffs();

      final standings = await standingsFuture;
      if (standings.isNotEmpty) {
        app.setCachedSeasonStandings(standings);
      }

      if (resolvedDoc != null && resolvedProgress != null) {
        if (resolvedDoc.dayNumber != app.cassandraMatchdayCursor) {
          await app.setCassandraMatchdayCursor(resolvedDoc.dayNumber);
        }

        final shouldUpdateCache =
            app.cachedPredictionMatches == null ||
            app.cachedPredictionMatches!.isEmpty ||
            app.cachedPredictionMatchesUpdatedAt == null ||
            resolvedDoc.updatedAt.isAfter(
              app.cachedPredictionMatchesUpdatedAt!,
            );

        if (shouldUpdateCache) {
          app.setCachedPredictionMatches(
            resolvedDoc.matches,
            isReal: true,
            updatedAt: resolvedDoc.updatedAt,
          );
          app.setCachedPredictionOutcomesByMatchId(
            resolvedDoc.outcomesByMatchId,
          );
          app.setRecentMatchdayDataBulk(
            matchesByMatchday: {resolvedDoc.dayNumber: resolvedDoc.matches},
            outcomesByMatchday: {
              resolvedDoc.dayNumber: resolvedDoc.outcomesByMatchId,
            },
          );
        } else {
          app.setCachedPredictionOutcomesByMatchId(
            resolvedDoc.outcomesByMatchId,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[live-sync] failed: $e');
      }
    } finally {
      _liveSyncInFlight = false;
    }
  }

  int _index = 0;

  static final _pages = <Widget>[
    PredictionsPage(),
    GroupPage(),
    SerieAPage(),
    ChatPage(),
    SettingsPage(),
  ];

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      // IndexedStack: mantiene lo stato delle pagine quando cambi tab.
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.navBarBg,
          indicatorColor: AppColors.navBarBg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Color(0xFFF6F4EF)),
          ),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Color(0xFFF6F4EF)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.sports_soccer),
              label: l10n.tabPredictions,
            ),
            NavigationDestination(
              icon: const Icon(Icons.groups),
              label: l10n.tabGroup,
            ),
            NavigationDestination(
              icon: const Icon(Icons.format_list_bulleted),
              label: l10n.tabLive,
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              label: l10n.tabChat,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings),
              label: l10n.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}
