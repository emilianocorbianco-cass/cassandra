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
import '../theme/cassandra_colors.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show MatchdayProgress, computeMatchdayProgress;
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../services/firestore/models/matchday_document.dart';
import '../../services/api_football/models/api_football_standing.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Timer? _liveSyncTimer;
  bool _liveSyncInFlight = false;
  bool _didInitialLiveSync = false;
  StreamSubscription<List<ApiFootballStanding>>? _standingsSub;

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

  void _bindStandingsStream() {
    if (_standingsSub != null) return; // bind solo una volta
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    _standingsSub = fs
        .streamSeasonStandings(seasonKey: app.currentSeasonKey)
        .listen((standings) {
          if (!mounted || standings.isEmpty) return;
          CassandraScope.of(context).setCachedSeasonStandings(standings);
        });
  }

  Future<void> _syncLiveFromBackend() async {
    if (!mounted || _liveSyncInFlight) return;

    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    _liveSyncInFlight = true;

    try {
      _bindStandingsStream();
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
      app.clearBackendSyncError();
    } catch (e) {
      app.markBackendSyncError(e);
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
    _standingsSub?.cancel();
    _liveSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = CassandraScope.of(context);

    return Scaffold(
      // IndexedStack: mantiene lo stato delle pagine quando cambi tab.
      body: Column(
        children: [
          if (app.hasBackendSyncError)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: CassandraColors.offlineBannerBg,
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: CassandraColors.offlineContent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.predictionsOfflineStatus,
                        style: const TextStyle(
                          color: CassandraColors.offlineContent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _index, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: CassandraColors.navBarBg,
          // Indicatore rosso semitrasparente — tab attivo distinguibile.
          indicatorColor: CassandraColors.primary.withValues(alpha: 0.28),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: CassandraColors.navBarFg),
          ),
          // Label bold sul tab selezionato.
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: CassandraColors.navBarFg,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              fontSize: 11,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.sports_soccer_outlined),
              selectedIcon: const Icon(Icons.sports_soccer),
              label: l10n.tabPredictions,
            ),
            NavigationDestination(
              icon: const Icon(Icons.groups_outlined),
              selectedIcon: const Icon(Icons.groups),
              label: l10n.tabGroup,
            ),
            NavigationDestination(
              // live_tv comunica meglio di format_list_bulleted
              icon: const Icon(Icons.live_tv_outlined),
              selectedIcon: const Icon(Icons.live_tv),
              label: l10n.tabLive,
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: l10n.tabChat,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l10n.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}
