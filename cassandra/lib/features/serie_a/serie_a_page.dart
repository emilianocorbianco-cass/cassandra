import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/state/app_state.dart';
import '../../app/widgets/team_name.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../group/widgets/group_matchday_leaderboard.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../../app/state/cassandra_scope.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  int _segment = 0; // 0 = risultati (last), 1 = classifica gruppo
  DateTime? _updatedAt;
  bool _didLoad = false;

  late Future<_SerieAData> _future;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _future = _load();
  }

  Future<_SerieAData> _load() async {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (app.cachedPredictionMatches != null &&
        app.cachedPredictionMatches!.isNotEmpty &&
        app.cachedPredictionMatchesAreReal) {
      _updatedAt = app.cachedPredictionMatchesUpdatedAt;
      return _SerieAData(
        matches: app.cachedPredictionMatches!,
        outcomesByMatchId: {
          for (final m in app.cachedPredictionMatches!)
            if (app.effectivePredictionOutcomesByMatchId[m.id] != null)
              m.id: app.effectivePredictionOutcomesByMatchId[m.id]!,
        },
        fromBackend: true,
      );
    }

    final fs = app.firestoreService;
    if (fs == null) {
      return const _SerieAData(
        matches: [],
        outcomesByMatchId: {},
        fromBackend: false,
      );
    }
    if (!app.isAuthenticated) {
      return _SerieAData(
        matches: const [],
        outcomesByMatchId: const {},
        fromBackend: false,
        errorMessage: l10n.serieASignInRequired,
      );
    }

    try {
      final doc = await fs.getMatchdayData(
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
      );
      if (doc == null || doc.matches.isEmpty) {
        return const _SerieAData(
          matches: [],
          outcomesByMatchId: {},
          fromBackend: false,
        );
      }

      _updatedAt = doc.updatedAt;
      app.setCachedPredictionMatches(
        doc.matches,
        isReal: true,
        updatedAt: doc.updatedAt,
      );
      app.setCachedPredictionOutcomesByMatchId(doc.outcomesByMatchId);
      return _SerieAData(
        matches: doc.matches,
        outcomesByMatchId: doc.outcomesByMatchId,
        fromBackend: true,
      );
    } catch (e) {
      return _SerieAData(
        matches: const [],
        outcomesByMatchId: const {},
        fromBackend: false,
        errorMessage: _friendlyBackendError(e, l10n, app),
      );
    }
  }

  String _friendlyBackendError(
    Object error,
    AppLocalizations l10n,
    AppState app,
  ) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return app.isAuthenticated
          ? l10n.backendPermissionDenied
          : l10n.serieASignInRequired;
    }
    final lower = error.toString().toLowerCase();
    if (lower.contains('permission-denied') ||
        lower.contains('permission denied')) {
      return app.isAuthenticated
          ? l10n.backendPermissionDenied
          : l10n.serieASignInRequired;
    }
    return error.toString();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serieATitle)),
      body: SafeArea(
        child: FutureBuilder<_SerieAData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;

            final demoMatches = app.cachedPredictionMatches;
            final demoActive =
                demoMatches != null && !app.cachedPredictionMatchesAreReal;

            final updatedLabel = _updatedAt == null
                ? ''
                : ' \u2022 ${l10n.shortUpdated} ${formatKickoff(_updatedAt!)}';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(l10n.serieASegmentResults),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(l10n.serieASegmentStandings),
                          ),
                        ],
                        selected: {_segment},
                        onSelectionChanged: (s) =>
                            setState(() => _segment = s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        demoActive
                            ? l10n.serieADataDemo
                            : (data?.errorMessage != null
                                  ? l10n.serieAErrorLoadingBackendCache(
                                      data?.errorMessage ?? '',
                                    )
                                  : (data?.fromBackend == true
                                        ? l10n.settingsDataBackendCache +
                                              updatedLabel
                                        : l10n.serieADataDemo)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _segment == 1
                      ? _buildGroupLeaderboard(context, app)
                      : RefreshIndicator(
                          onRefresh: demoActive ? () async {} : _reload,
                          child: demoActive
                              ? _buildDemoList(
                                  context,
                                  _segment,
                                  demoMatches,
                                  app.cachedPredictionOutcomesByMatchId,
                                  l10n,
                                )
                              : _buildList(
                                  context,
                                  data ??
                                      const _SerieAData(
                                        matches: [],
                                        outcomesByMatchId: {},
                                        fromBackend: false,
                                      ),
                                ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupLeaderboard(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context)!;
    final cachedMatches = appState.cachedPredictionMatches;
    if (cachedMatches == null || cachedMatches.isEmpty) {
      return Center(child: Text(l10n.serieANoMatchDataAvailable));
    }

    final outcomesByMatchId = appState.cachedPredictionMatchesAreReal
        ? <String, MatchOutcome>{
            for (final m in cachedMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          }
        : <String, MatchOutcome>{};

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicks = appState.currentUserPicksByMatchId;

    final overridePicksByMemberId = <String, Map<String, PickOption>>{
      ...appState.memberPicksByMemberId,
      overrideMember.id: currentUserPicks,
    };

    return GroupMatchdayLeaderboard(
      matches: cachedMatches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );
  }

  Widget _buildList(BuildContext context, _SerieAData data) {
    final l10n = AppLocalizations.of(context)!;
    final matches = List<PredictionMatch>.of(data.matches)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (matches.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.serieANoMatchesToShow)),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: matches.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = matches[i];
        final o = data.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        final trailing = o.isPending ? '—' : o.label.toUpperCase();

        return Card(
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: TeamName(
                    name: m.homeTeam,
                    logoUrl: m.homeTeamLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('  ${l10n.commonVersusShort}  '),
                Expanded(
                  child: TeamName(
                    name: m.awayTeam,
                    logoUrl: m.awayTeamLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    reversed: true,
                  ),
                ),
              ],
            ),
            subtitle: Text('${l10n.kickoffLabel}: ${formatKickoff(m.kickoff)}'),
            trailing: Text(
              trailing,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

class _SerieAData {
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final bool fromBackend;
  final String? errorMessage;

  const _SerieAData({
    required this.matches,
    required this.outcomesByMatchId,
    required this.fromBackend,
    this.errorMessage,
  });
}

Widget _buildDemoList(
  BuildContext context,
  int segment,
  List<PredictionMatch> all,
  Map<String, MatchOutcome> outcomes,
  AppLocalizations l10n,
) {
  final matches = all.where((m) {
    final o = outcomes[m.id] ?? MatchOutcome.pending;
    return segment == 0 ? !o.isPending : o.isPending;
  }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

  if (matches.isEmpty) {
    return Center(
      child: Text(
        segment == 0 ? l10n.serieANoResults : l10n.serieANoUpcomingMatches,
      ),
    );
  }

  return ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    itemCount: matches.length,
    separatorBuilder: (context, index) => const SizedBox(height: 12),
    itemBuilder: (context, i) {
      final m = matches[i];
      final o = outcomes[m.id] ?? MatchOutcome.pending;
      final subtitle = '${l10n.kickoffLabel}: ${formatKickoff(m.kickoff)}';
      final trailing = o.isPending ? '' : _demoOutcomeLabel(o);

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TeamName(
                            name: m.homeTeam,
                            logoUrl: m.homeTeamLogo,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '  vs  ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Expanded(
                          child: TeamName(
                            name: m.awayTeam,
                            logoUrl: m.awayTeamLogo,
                            style: Theme.of(context).textTheme.titleMedium,
                            reversed: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty)
                Text(trailing, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    },
  );
}

String _demoOutcomeLabel(MatchOutcome o) {
  final raw = o.toString().split('.').last;
  if (raw == 'home') return '1';
  if (raw == 'draw') return 'X';
  if (raw == 'away') return '2';
  return raw.toUpperCase();
}
