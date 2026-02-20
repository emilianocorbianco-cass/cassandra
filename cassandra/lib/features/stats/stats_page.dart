import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import 'models/group_metric.dart';
import 'models/player_season_stats.dart';
import 'stats_engine.dart';
import 'widgets/stats_entries_loader.dart';
import 'widgets/group_stats_view.dart';
import 'widgets/personal_stats_view.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    this.embedded = false,
    this.lockToPersonal = false,
    this.lockToGroup = false,
    this.initialSegment = 0,
  });

  final bool embedded;
  final bool lockToPersonal;
  final bool lockToGroup;
  final int initialSegment;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late int _segment; // 0 = personali, 1 = gruppo
  GroupMetric _metric = GroupMetric.avgPoints;

  List<SeasonLeaderboardEntry> _entries = const [];
  List<PlayerSeasonStats> _stats = const [];

  String? _selectedMemberId;
  bool _loading = false;
  bool _loadRequested = false;
  String? _loadedGroupId;

  @override
  void initState() {
    super.initState();
    if (widget.lockToPersonal) {
      _segment = 0;
    } else if (widget.lockToGroup) {
      _segment = 1;
    } else {
      _segment = widget.initialSegment.clamp(0, 1).toInt();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  bool _canUseFirestoreStats(AppState app) =>
      app.firestoreService != null &&
      app.isAuthenticated &&
      app.activeGroupId != null;

  void _ensureLoaded() {
    final app = CassandraScope.of(context);
    final groupId = app.activeGroupId;
    final shouldReload = !_loadRequested || _loadedGroupId != groupId;
    if (!shouldReload) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadStats();
    });
  }

  Future<List<SeasonLeaderboardEntry>> _loadEntriesFromFirestore(
    AppState app,
  ) => StatsEntriesLoader.loadEntriesFromFirestore(app);

  Future<void> _loadStats() async {
    final app = CassandraScope.of(context);
    setState(() => _loading = true);

    try {
      final currentUser = StatsEntriesLoader.currentUserMember(app);
      List<SeasonLeaderboardEntry> entries;
      if (_canUseFirestoreStats(app)) {
        entries = await _loadEntriesFromFirestore(app);
      } else {
        entries = [StatsEntriesLoader.emptyEntryFor(currentUser)];
      }

      if (entries.isEmpty) {
        entries = [StatsEntriesLoader.emptyEntryFor(currentUser)];
      } else if (!entries.any((e) => e.member.id == currentUser.id)) {
        entries = [...entries, StatsEntriesLoader.emptyEntryFor(currentUser)];
      }

      final stats = CassandraStatsEngine.computeForEntries(entries);
      final selectedId =
          (_selectedMemberId != null &&
              entries.any((e) => e.member.id == _selectedMemberId))
          ? _selectedMemberId
          : entries.first.member.id;

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stats = stats;
        _selectedMemberId = selectedId;
        _loading = false;
        _loadedGroupId = app.activeGroupId;
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = StatsEntriesLoader.emptyEntryFor(
        StatsEntriesLoader.currentUserMember(app),
      );
      setState(() {
        _entries = [fallback];
        _stats = CassandraStatsEngine.computeForEntries(_entries);
        _selectedMemberId = fallback.member.id;
        _loading = false;
        _loadedGroupId = app.activeGroupId;
      });
    }
  }

  PlayerSeasonStats? get _selectedStats {
    if (_stats.isEmpty || _selectedMemberId == null) return null;
    return _stats.firstWhere(
      (stat) => stat.member.id == _selectedMemberId,
      orElse: () => _stats.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final l10n = AppLocalizations.of(context)!;

    final content = SafeArea(
      top: !widget.embedded,
      bottom: !widget.embedded,
      child: Column(
        children: [
          if (!widget.lockToPersonal && !widget.lockToGroup)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(l10n.statsSegmentPersonal),
                  ),
                  ButtonSegment(value: 1, label: Text(l10n.statsSegmentGroup)),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading && _entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? Center(child: Text(l10n.commonNoDataAvailable))
                : (widget.lockToPersonal || _segment == 0)
                ? PersonalStatsView(
                    entries: _entries,
                    stats: _selectedStats,
                    selectedMemberId: _selectedMemberId,
                    onMemberSelected: (v) =>
                        setState(() => _selectedMemberId = v),
                    loading: _loading,
                  )
                : GroupStatsView(
                    entries: _entries,
                    metric: _metric,
                    onMetricChanged: (m) => setState(() => _metric = m),
                  ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.statsTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: content,
    );
  }
}
