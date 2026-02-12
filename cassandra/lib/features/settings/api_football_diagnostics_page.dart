import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../features/predictions/models/formatters.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';

class ApiFootballDiagnosticsPage extends StatefulWidget {
  const ApiFootballDiagnosticsPage({super.key});

  @override
  State<ApiFootballDiagnosticsPage> createState() =>
      _ApiFootballDiagnosticsPageState();
}

class _ApiFootballDiagnosticsPageState
    extends State<ApiFootballDiagnosticsPage> {
  late Future<_BackendDiagData> _future;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _future = _load();
  }

  Future<_BackendDiagData> _load() async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null) {
      return const _BackendDiagData(
        matches: [],
        outcomesByMatchId: {},
        errorMessage: 'Backend/Firestore non configurato su questo device.',
      );
    }

    try {
      final doc = await fs.getMatchdayData(
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
      );

      if (doc == null || doc.matches.isEmpty) {
        return _BackendDiagData(
          matches: const [],
          outcomesByMatchId: const {},
          seasonKey: app.currentSeasonKey,
          dayNumber: app.cassandraMatchdayCursor,
          updatedAt: null,
          errorMessage: 'Nessun documento matchday trovato in Firestore.',
        );
      }

      return _BackendDiagData(
        matches: doc.matches,
        outcomesByMatchId: doc.outcomesByMatchId,
        seasonKey: doc.seasonKey,
        dayNumber: doc.dayNumber,
        updatedAt: doc.updatedAt,
      );
    } catch (e) {
      return _BackendDiagData(
        matches: const [],
        outcomesByMatchId: const {},
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
        updatedAt: null,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend cache diagnostica'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_BackendDiagData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data =
              snap.data ??
              const _BackendDiagData(matches: [], outcomesByMatchId: {});

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Sorgente: Firestore /seasons/<season>/matchdays/<day>',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (data.seasonKey != null) Text('seasonKey: ${data.seasonKey}'),
              if (data.dayNumber != null) Text('dayNumber: ${data.dayNumber}'),
              Text('matches: ${data.matches.length}'),
              Text('outcomes: ${data.outcomesByMatchId.length}'),
              Text(
                'updatedAt: ${data.updatedAt == null ? '-' : formatKickoff(data.updatedAt!)}',
              ),
              if (data.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text('Errore', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(data.errorMessage!),
              ],
              const SizedBox(height: 14),
              if (data.matches.isEmpty)
                const Text('Nessuna partita disponibile.'),
              ...data.matches.map((m) {
                final o = data.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
                return Card(
                  child: ListTile(
                    title: Text('${m.homeTeam}  vs  ${m.awayTeam}'),
                    subtitle: Text(formatKickoff(m.kickoff)),
                    trailing: Text(
                      o.isPending ? 'PENDING' : o.label.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _BackendDiagData {
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final String? seasonKey;
  final int? dayNumber;
  final DateTime? updatedAt;
  final String? errorMessage;

  const _BackendDiagData({
    required this.matches,
    required this.outcomesByMatchId,
    this.seasonKey,
    this.dayNumber,
    this.updatedAt,
    this.errorMessage,
  });
}
