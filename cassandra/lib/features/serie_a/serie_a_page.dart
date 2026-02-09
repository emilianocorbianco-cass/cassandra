import 'package:flutter/material.dart';

import '../../app/config/env.dart';
import '../../app/widgets/team_name.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_service.dart';
import '../../services/api_football/models/api_football_fixture.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../group/widgets/group_matchday_leaderboard.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import 'adapters/fixture_result_adapter.dart';
import '../../app/state/cassandra_scope.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  int _segment = 0; // 0 = risultati (last), 1 = classifica gruppo
  DateTime? _updatedAt;

  late Future<_SerieAData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String? _safeApiKey() {
    // In test env dotEnv può non essere inizializzato → non dobbiamo crashare.
    try {
      final raw = Env.apiFootballKey;
      final k = raw?.trim();
      if (k == null || k.isEmpty) return null;
      return k;
    } catch (_) {
      return null;
    }
  }

  Future<_SerieAData> _load() async {
    final key = _safeApiKey();
    if (key == null) {
      return const _SerieAData(
        last: [],
        next: [],
        errorMessage: 'API key mancante (Settings → env).',
      );
    }

    final client = ApiFootballClient(
      apiKey: key,
      baseUrl: Env.baseUrl,
      useRapidApi: Env.useRapidApi,
      rapidApiHost: Env.rapidApiHost,
    );

    try {
      final service = ApiFootballService(client);

      final last = await service.getLastSerieAFixtures(count: 10);
      final next = await service.getNextSerieAFixtures(count: 10);

      _updatedAt = DateTime.now();
      return _SerieAData(last: last, next: next);
    } catch (e) {
      return _SerieAData(
        last: const [],
        next: const [],
        errorMessage: 'Errore caricando fixture: $e',
      );
    } finally {
      client.close();
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: SafeArea(
        child: FutureBuilder<_SerieAData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;

            final appState = CassandraScope.of(context);
            final demoMatches = appState.cachedPredictionMatches;
            final demoActive =
                demoMatches != null && !appState.cachedPredictionMatchesAreReal;

            final updatedLabel = _updatedAt == null
                ? ''
                : ' • agg. ${formatKickoff(_updatedAt!)}';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('risultati')),
                          ButtonSegment(value: 1, label: Text('classifica')),
                        ],
                        selected: {_segment},
                        onSelectionChanged: (s) =>
                            setState(() => _segment = s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        demoActive
                            ? 'dati: demo'
                            : (data?.errorMessage != null
                                  ? data!.errorMessage!
                                  : (demoActive
                                        ? 'dati: demo'
                                        : 'dati: reali (API)$updatedLabel')),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _segment == 1
                      ? _buildGroupLeaderboard(context, appState)
                      : RefreshIndicator(
                          onRefresh: demoActive ? () async {} : _reload,
                          child: demoActive
                              ? _buildDemoList(
                                  context,
                                  _segment,
                                  demoMatches,
                                  appState.cachedPredictionOutcomesByMatchId,
                                )
                              : _buildList(context, snap),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupLeaderboard(BuildContext context, dynamic appState) {
    final cachedMatches = appState.cachedPredictionMatches as List<PredictionMatch>?;
    if (cachedMatches == null || cachedMatches.isEmpty) {
      return const Center(child: Text('Nessun dato partite disponibile'));
    }

    final outcomesByMatchId = appState.cachedPredictionMatchesAreReal
        ? <String, MatchOutcome>{
            for (final m in cachedMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          }
        : <String, MatchOutcome>{};

    final overrideMember = GroupMember(
      id: appState.profile.id as String,
      displayName: appState.profile.displayName as String,
      teamName: appState.profile.teamName as String,
      avatarSeed: appState.currentUserAvatarSeed as int,
      favoriteTeam: appState.profile.favoriteTeam as String?,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicks =
        appState.currentUserPicksByMatchId as Map<String, PickOption>;

    final overridePicksByMemberId = <String, Map<String, PickOption>>{
      ...(appState.memberPicksByMemberId as Map<String, Map<String, PickOption>>),
      overrideMember.id: currentUserPicks,
    };

    return GroupMatchdayLeaderboard(
      matches: cachedMatches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );
  }

  Widget _buildList(BuildContext context, AsyncSnapshot<_SerieAData> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return ListView(
        children: const [
          SizedBox(height: 240),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final data =
        snap.data ??
        const _SerieAData(last: [], next: [], errorMessage: 'Nessun dato.');

    final fixtures = _segment == 0 ? data.last : data.next;

    if (fixtures.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Nessuna partita da mostrare')),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: fixtures.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f = fixtures[i];

        final score = fixtureScoreLabel(f);
        final out = fixtureOutcomeLabel(f); // 1/X/2 oppure ""
        final trailing = out.isEmpty ? score : '$score\n$out';

        final kickoffLocal = f.kickoffUtc.toLocal();

        final extra = <String>[];
        if (f.round != null && f.round!.trim().isNotEmpty) {
          extra.add(f.round!.trim());
        }
        // Nei "risultati" è utile vedere lo status (FT, AET, ecc.)
        if (_segment == 0 && f.statusShort.trim().isNotEmpty) {
          extra.add(f.statusShort.trim());
        }

        final extraLabel = extra.isEmpty ? '' : ' • ${extra.join(' • ')}';

        return Card(
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: TeamName(
                    name: f.homeName,
                    logoUrl: f.homeLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('  vs  '),
                Expanded(
                  child: TeamName(
                    name: f.awayName,
                    logoUrl: f.awayLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    reversed: true,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'Kickoff: ${formatKickoff(kickoffLocal)}$extraLabel',
            ),
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
  final List<ApiFootballFixture> last;
  final List<ApiFootballFixture> next;
  final String? errorMessage;

  const _SerieAData({
    required this.last,
    required this.next,
    this.errorMessage,
  });
}

Widget _buildDemoList(
  BuildContext context,
  int segment,
  List<PredictionMatch> all,
  Map<String, MatchOutcome> outcomes,
) {
  final matches = all.where((m) {
    final o = outcomes[m.id] ?? MatchOutcome.pending;
    return segment == 0 ? !o.isPending : o.isPending;
  }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

  if (matches.isEmpty) {
    return Center(
      child: Text(
        segment == 0 ? 'Nessun risultato' : 'Nessuna partita in programma',
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
      final subtitle = 'Kickoff: ${formatKickoff(m.kickoff)}';
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
                        Text('  vs  ', style: Theme.of(context).textTheme.titleMedium),
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
