import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

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

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
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
      // This corrects the cursor if it drifted (auto-advance overshoot, stale
      // cache, etc.) regardless of direction.
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
            debugPrint(
              '[live-sync] API says current matchday is $apiResolvedDay '
              '(cursor was $dayNumber), correcting',
            );
            dayNumber = apiResolvedDay;
            await app.setCassandraMatchdayCursor(apiResolvedDay);
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

  // -1 = GroupHubPage, 0..3 = tab pages
  int _index = 0;
  bool get _showingGroupHub => _index == -1;
  int _slideDirection = 1; // 1 = forward (left), -1 = backward (right)
  late final AnimationController _bubbleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final CurvedAnimation _bubbleCurve = CurvedAnimation(
    parent: _bubbleCtrl,
    curve: Curves.easeOutBack,
  );
  double _bubbleFrom = 0;
  double _bubbleTo = 0;

  void _selectTab(int i) {
    if (i == _index) return;
    setState(() {
      _slideDirection = i > _index ? 1 : -1;
      _bubbleFrom = _index.toDouble();
      _bubbleTo = i.toDouble();
      _index = i;
      _bubbleCtrl.forward(from: 0);
    });
  }

  // ── Swipe navigation ────────────────────────────────────────────────────
  double _swipeDx = 0;
  static const _swipeThreshold = 40.0;
  static const _swipeVelocityThreshold = 400.0;
  static const _swipeMinDxForVelocity = 15.0;

  void _onHorizontalDragStart(DragStartDetails _) {
    _swipeDx = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _swipeDx += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final swipeRight = _swipeDx > _swipeThreshold ||
        (_swipeDx > _swipeMinDxForVelocity && velocity > _swipeVelocityThreshold);
    final swipeLeft = _swipeDx < -_swipeThreshold ||
        (_swipeDx < -_swipeMinDxForVelocity && velocity < -_swipeVelocityThreshold);

    if (swipeLeft && _index < _pages.length - 1) {
      _selectTab(_index + 1);
    } else if (swipeRight && _index > -1) {
      _selectTab(_index - 1);
    }
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
    _bubbleCurve.dispose();
    _bubbleCtrl.dispose();
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
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        // The incoming page has key == _index; outgoing has old key.
                        final isIncoming = child.key == ValueKey(_index);
                        final offset = Tween<Offset>(
                          begin: Offset(
                            isIncoming ? _slideDirection.toDouble() : -_slideDirection.toDouble(),
                            0,
                          ),
                          end: Offset.zero,
                        );
                        return SlideTransition(
                          position: offset.animate(animation),
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_index),
                        child: _showingGroupHub
                            ? GroupHubPage(onBack: () => _selectTab(0))
                            : _pages[_index],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Floating liquid-glass tab bar ──────────────────────────
          if (!_showingGroupHub) Positioned(
            left: 18,
            right: 18,
            bottom: Platform.isAndroid
                ? MediaQuery.of(context).viewPadding.bottom + 6
                : 14 + MediaQuery.of(context).viewPadding.bottom * 0.3,
            child: Container(
                  height: 50,
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
                          // ── Pill highlight (Fitness-style) ─────
                          AnimatedBuilder(
                            animation: _bubbleCtrl,
                            builder: (context, _) {
                              final t = _bubbleCurve.value;
                              final pos = lerpDouble(
                                _bubbleFrom,
                                _bubbleTo,
                                t,
                              )!;
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

