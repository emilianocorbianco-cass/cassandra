import 'package:flutter/material.dart';
import 'dart:async';

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';

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

      // Serie A has 38 matchdays. A cursor beyond that is a stale artefact;
      // reset to a safe default so the look-ahead can rediscover the current
      // matchday from Firestore.
      const maxSerieAMatchday = 38;
      const safeCursorReset = 20;
      if (dayNumber > maxSerieAMatchday) {
        debugPrint(
          '[live-sync] cursor $dayNumber > $maxSerieAMatchday, '
          'resetting to $safeCursorReset',
        );
        dayNumber = safeCursorReset;
        await app.setCassandraMatchdayCursor(safeCursorReset);
      }

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
        if (!progress.readyToAdvance) break;
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

    // Platinum background: sfondo unico dell'intera app.
    // Le card e gli altri elementi si appoggiano sopra.
    return Scaffold(
        backgroundColor: CassandraColors.bg,
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
        bottomNavigationBar: Container(
          color: CassandraColors.inkBlackV2,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(
                children: [
                  _NavTab(
                    icon: Icons.sports_soccer_outlined,
                    selectedIcon: Icons.sports_soccer,
                    label: l10n.tabPredictions,
                    selected: _index == 0,
                    onTap: () => setState(() => _index = 0),
                  ),
                  _NavTab(
                    icon: Icons.groups_outlined,
                    selectedIcon: Icons.groups,
                    label: l10n.tabGroup,
                    selected: _index == 1,
                    onTap: () => setState(() => _index = 1),
                  ),
                  _NavTab(
                    icon: Icons.live_tv_outlined,
                    selectedIcon: Icons.live_tv,
                    label: l10n.tabLive,
                    selected: _index == 2,
                    onTap: () => setState(() => _index = 2),
                  ),
                  _NavTab(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: l10n.tabSettings,
                    selected: _index == 3,
                    onTap: () => setState(() => _index = 3),
                  ),
                ],
              ),
            ),
          ),
        ),
    ); // Scaffold
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              color: CassandraColors.brightSnow,
              size: selected ? 30 : 28,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: CassandraColors.brightSnow,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
