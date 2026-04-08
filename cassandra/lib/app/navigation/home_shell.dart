import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';
import '../../features/group/group_hub_page.dart';
import '../../features/settings/settings_page.dart';
import 'package:cassandra/features/serie_a/serie_a_page.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import '../theme/cassandra_colors.dart';
import '../widgets/target_icon.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show computeMatchdayProgress;
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../services/api_football/models/api_football_standing.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_service.dart';
import '../../features/predictions/adapters/api_football_fixture_adapter.dart';
import '../../services/storage/storage_service.dart';
import '../config/env.dart';

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
      unawaited(_preWarmGroupMemberPhotos());
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
      final now = app.now();
      var dayNumber = app.cassandraMatchdayCursor;
      app.ensureOriginKickoffsLoaded();

      // Ask API-Football for the actual current matchday round.
      // Only accept a FORWARD move if the current matchday is finalized
      // in Firestore (all matches done). This prevents jumping to X+1
      // while X still has live matches.
      int? apiResolvedDay;
      final apiKey = Env.apiFootballKey;
      if (apiKey != null) {
        try {
          final client = ApiFootballClient(
            apiKey: apiKey,
            baseUrl: Env.baseUrl,
            useRapidApi: Env.useRapidApi,
            rapidApiHost: Env.rapidApiHost,
          );
          final apiService = ApiFootballService(client);
          apiResolvedDay = await apiService.getCurrentSerieAMatchday();
          if (apiResolvedDay != null && apiResolvedDay != dayNumber) {
            if (apiResolvedDay < dayNumber) {
              debugPrint(
                '[live-sync] API says current matchday is $apiResolvedDay '
                '(cursor was $dayNumber), correcting backward',
              );
              dayNumber = apiResolvedDay;
              await app.setCassandraMatchdayCursor(apiResolvedDay);
            } else {
              final currentDoc = await fs.getMatchdayData(
                seasonKey: app.currentSeasonKey,
                dayNumber: dayNumber,
              );
              if (currentDoc != null && currentDoc.finalized) {
                debugPrint(
                  '[live-sync] API says current matchday is $apiResolvedDay '
                  '(cursor was $dayNumber, finalized), advancing',
                );
                dayNumber = apiResolvedDay;
                await app.setCassandraMatchdayCursor(apiResolvedDay);
              } else {
                debugPrint(
                  '[live-sync] API says $apiResolvedDay but matchday '
                  '$dayNumber not finalized yet, staying',
                );
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[live-sync] API getCurrentMatchday failed: $e');
          }
        }
      }

      // Serie A has 38 matchdays. If the cursor is at or beyond the last
      // matchday it may be a stale artefact (e.g. intermediate matchdays were
      // deleted and the look-ahead jumped ahead). Reset to a safe value so the
      // look-ahead can rediscover the earliest pending matchday from Firestore.
      const maxSerieAMatchday = 38;
      const maxLookAheadDays = 12;
      final safeCursorReset = maxSerieAMatchday - maxLookAheadDays; // 26
      if (dayNumber >= maxSerieAMatchday) {
        debugPrint(
          '[live-sync] cursor $dayNumber >= $maxSerieAMatchday, '
          'resetting to $safeCursorReset',
        );
        dayNumber = safeCursorReset;
        await app.setCassandraMatchdayCursor(safeCursorReset);
      }

      // 1. Try Firestore for the exact cursor day.
      final firestoreDoc = await fs.getMatchdayData(
        seasonKey: app.currentSeasonKey,
        dayNumber: dayNumber,
      );

      List<PredictionMatch>? resolvedMatches;
      Map<String, MatchOutcome> resolvedOutcomes = const {};

      if (firestoreDoc != null && firestoreDoc.matches.isNotEmpty) {
        resolvedMatches = firestoreDoc.matches;
        resolvedOutcomes = firestoreDoc.outcomesByMatchId;
      }

      // 2. Fallback: fetch fixtures from API-Football for the current round.
      if (resolvedMatches == null && apiKey != null) {
        try {
          final client = ApiFootballClient(
            apiKey: apiKey,
            baseUrl: Env.baseUrl,
            useRapidApi: Env.useRapidApi,
            rapidApiHost: Env.rapidApiHost,
          );
          final apiService = ApiFootballService(client);
          final roundLabel = 'Regular Season - $dayNumber';
          final apiFixtures = await apiService.getSerieAFixturesForRound(
            round: roundLabel,
          );
          if (apiFixtures.isNotEmpty) {
            resolvedMatches = predictionMatchesFromFixtures(
              apiFixtures,
              useMockIds: false,
              matchdayNumber: dayNumber,
            );
            debugPrint(
              '[live-sync] loaded ${resolvedMatches.length} fixtures '
              'from API for round $dayNumber',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[live-sync] API fixtures fetch failed: $e');
          }
        }
      }

      if (resolvedMatches != null && resolvedMatches.isNotEmpty) {
        for (final m in resolvedMatches) {
          app.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
        }

        String statusFor(PredictionMatch m) =>
            (resolvedOutcomes[m.id] ?? MatchOutcome.pending).isGraded
                ? 'FT'
                : 'NS';
        final progress = computeMatchdayProgress<PredictionMatch>(
          resolvedMatches,
          now: now,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) =>
              app.originKickoffFor(matchId: m.id, fallbackKickoff: m.kickoff),
          statusShort: (m) => statusFor(m),
        );

        app.setMatchdayProgress(
          matchdayNumber: dayNumber,
          progress: progress,
          allowAutoAdvance: false,
        );

        app.setCachedPredictionMatches(
          resolvedMatches,
          isReal: true,
          updatedAt: firestoreDoc?.updatedAt ?? DateTime.now(),
        );
        app.setCachedPredictionOutcomesByMatchId(resolvedOutcomes);
        app.setRecentMatchdayDataBulk(
          matchesByMatchday: {dayNumber: resolvedMatches},
          outcomesByMatchday: {dayNumber: resolvedOutcomes},
        );
      }

      await app.persistOriginKickoffs();
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

  /// Pre-warm member photo caches at app startup so photos are
  /// instant when the user opens the group tab.
  Future<void> _preWarmGroupMemberPhotos() async {
    final app = CassandraScope.of(context);
    if (!app.hasGroup || app.firestoreService == null) return;
    try {
      final members = await app.fetchFirestoreGroupMembers();
      final fs = app.firestoreService!;
      final storage = StorageService();

      // Pre-warm StorageService byte cache for members who already
      // have a storage:// photoUrl in their member doc.
      for (final m in members) {
        if (m.photoUrl != null &&
            StorageService.isStorageReference(m.photoUrl!)) {
          unawaited(storage.readBytesByReference(m.photoUrl!));
        }
      }

      // For members with no photoUrl in member doc, fetch user docs.
      final missingUids = <String>[
        for (final m in members)
          if (m.photoUrl == null &&
              !GroupPage.memberPhotoCache.containsKey(m.id))
            m.id,
      ];
      if (missingUids.isEmpty) return;

      final profiles = await Future.wait(
        missingUids.map((uid) => fs.getUserProfile(uid)),
      );
      for (var j = 0; j < missingUids.length; j++) {
        final profile = profiles[j];
        if (profile == null) continue;
        final photo = ((profile['photoUrl'] as String?) ?? '').trim();
        if (photo.isEmpty) continue;
        GroupPage.memberPhotoCache[missingUids[j]] = photo;
        if (StorageService.isStorageReference(photo)) {
          unawaited(storage.readBytesByReference(photo));
        }
      }
    } catch (_) {
      // Best-effort — don't break app init.
    }
  }

  int _index = 0;
  late final PageController _pageCtrl = PageController();
  bool _groupHubTriggered = false;

  void _selectTab(int i) {
    if (i == _index) return;
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int page) {
    setState(() => _index = page);
  }

  void _openGroupHub() {
    final app = CassandraScope.of(context);
    if (!app.isAuthenticated) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GroupHubPage(
          onBack: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  bool _handleHorizontalOverscroll(ScrollNotification notification) {
    if (_index != 0) return false;
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification) {
      _groupHubTriggered = false;
    }
    if (_groupHubTriggered) return false;
    if (notification is OverscrollNotification && notification.overscroll < -8) {
      _groupHubTriggered = true;
      _openGroupHub();
    }
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels < -50) {
      _groupHubTriggered = true;
      _openGroupHub();
    }
    return false;
  }

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
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = CassandraScope.of(context);

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: Stack(
        children: [
          // ── Content fills entire screen ────────────────────────────
          Column(
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
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleHorizontalOverscroll,
                  child: PageView(
                    controller: _pageCtrl,
                    onPageChanged: _onPageChanged,
                    children: _pages,
                  ),
                ),
              ),
            ],
          ),

          // ── Floating liquid-glass tab bar ──────────────────────────
          Positioned(
            left: 18,
            right: 18,
            bottom: Platform.isAndroid
                ? MediaQuery.of(context).viewPadding.bottom + 3
                : 11 + MediaQuery.of(context).viewPadding.bottom * 0.3,
            child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tabW = constraints.maxWidth / 4;
                      final barH = constraints.maxHeight;
                      return Stack(
                        children: [
                          // ── Pill highlight (tracks PageView position) ─────
                          AnimatedBuilder(
                            animation: _pageCtrl,
                            builder: (context, _) {
                              final pos = _pageCtrl.hasClients
                                  ? (_pageCtrl.page ?? _index.toDouble())
                                  : _index.toDouble();
                              const hPad = 4.0;
                              const vPad = 5.0;
                              final left = pos * tabW + hPad;
                              final pillW = tabW - hPad * 2;
                              final pillH = barH - vPad * 2;
                              return Positioned(
                                left: left,
                                top: vPad,
                                child: Container(
                                  width: pillW,
                                  height: pillH,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.white.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // ── Tab items (fill height, centered) ──
                          SizedBox.expand(
                            child: Row(
                              children: [
                                _NavTab(
                                  iconBuilder: (color, size) =>
                                      TargetIcon(size: size, color: color),
                                  label: l10n.tabPredictions,
                                  selected: _index == 0,
                                  onTap: () => _selectTab(0),
                                ),
                                _NavTab(
                                  icon: Icons.groups_outlined,
                                  selectedIcon: Icons.groups,
                                  label: l10n.tabGroup,
                                  selected: _index == 1,
                                  onTap: () => _selectTab(1),
                                ),
                                _NavTab(
                                  icon: Icons.sports_soccer_outlined,
                                  selectedIcon: Icons.sports_soccer,
                                  label: l10n.tabLive,
                                  selected: _index == 2,
                                  onTap: () => _selectTab(2),
                                ),
                                _NavTab(
                                  icon: Icons.settings_outlined,
                                  selectedIcon: Icons.settings,
                                  label: l10n.tabSettings,
                                  selected: _index == 3,
                                  onTap: () => _selectTab(3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    this.icon,
    this.selectedIcon,
    this.iconBuilder,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final IconData? selectedIcon;
  /// Custom widget builder that receives the color and size.
  final Widget Function(Color color, double size)? iconBuilder;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  bool _wasSelected = false;

  @override
  void didUpdateWidget(_NavTab old) {
    super.didUpdateWidget(old);
    if (widget.selected && !_wasSelected) {
      _flash.forward(from: 0);
    }
    _wasSelected = widget.selected;
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _flash,
          builder: (context, _) {
            const selectedColor = CassandraColors.brightSnow;
            final color = widget.selected
                ? selectedColor
                : CassandraColors.brightSnow;

            const double iconSize = 26.0;
            final iconWidget = widget.iconBuilder != null
                ? widget.iconBuilder!(color, iconSize)
                : Icon(
                    widget.selected ? widget.selectedIcon : widget.icon,
                    color: color,
                    size: iconSize,
                  );
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: FittedBox(child: iconWidget),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

