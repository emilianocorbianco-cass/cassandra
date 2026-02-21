import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool _seedLoading = false;
  String? _seedResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _future = _load();
  }

  Future<_BackendDiagData> _load() async {
    final l10n = AppLocalizations.of(context)!;
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null) {
      return _BackendDiagData(
        matches: [],
        outcomesByMatchId: {},
        errorMessage: l10n.settingsBackendNotConfigured,
      );
    }
    if (!app.isAuthenticated) {
      return _BackendDiagData(
        matches: [],
        outcomesByMatchId: {},
        errorMessage: l10n.groupSignInRequired,
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
          errorMessage: l10n.settingsDiagNoMatchdayDoc,
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
      final errorMessage =
          e is FirebaseException && e.code == 'permission-denied'
          ? l10n.backendPermissionDenied
          : e.toString();
      return _BackendDiagData(
        matches: const [],
        outcomesByMatchId: const {},
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
        updatedAt: null,
        errorMessage: errorMessage,
      );
    }
  }

  Future<void> _seedMockData() async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null) {
      setState(() => _seedResult = 'FirestoreService non disponibile.');
      return;
    }
    setState(() {
      _seedLoading = true;
      _seedResult = null;
    });
    try {
      final result = await fs.seedMockGroupMembers(
        inviteCode: 'CASS-6G2N',
        seasonKey: app.currentSeasonKey,
        dayNumber: 26,
      );
      if (mounted) setState(() => _seedResult = result);
    } catch (e) {
      if (mounted) setState(() => _seedResult = 'Errore: $e');
    } finally {
      if (mounted) setState(() => _seedLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsBackendDiagnosticsTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsRefreshCacheNowTitle,
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
                l10n.settingsDiagSourceFirestore,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (data.seasonKey != null)
                Text(l10n.settingsDiagSeasonKey(data.seasonKey!)),
              if (data.dayNumber != null)
                Text(l10n.settingsDiagDayNumber(data.dayNumber!)),
              Text(l10n.settingsDiagMatchesCount(data.matches.length)),
              Text(
                l10n.settingsDiagOutcomesCount(data.outcomesByMatchId.length),
              ),
              Text(
                l10n.settingsDiagUpdatedAt(
                  data.updatedAt == null ? '-' : formatKickoff(data.updatedAt!),
                ),
              ),
              if (data.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.settingsDiagErrorTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(data.errorMessage!),
              ],
              const SizedBox(height: 14),
              if (data.matches.isEmpty) Text(l10n.serieANoMatchesToShow),
              ...data.matches.map((m) {
                final o = data.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
                return Card(
                  child: ListTile(
                    title: Text('${m.homeTeam}  vs  ${m.awayTeam}'),
                    subtitle: Text(formatKickoff(m.kickoff)),
                    trailing: Text(
                      o.isPending
                          ? l10n.predictionsOutcomePending.toUpperCase()
                          : o.label.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }),

              // ── Dev: seed mock group members ────────────────────────────
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '🛠 Dev Tools',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Aggiunge Topolino e Pippo al gruppo CASS-6G2N con pick '
                'per la giornata 26 della stagione corrente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _seedLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('Seed Mock Users (CASS-6G2N · G26)'),
                onPressed: _seedLoading ? null : _seedMockData,
              ),
              if (_seedResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _seedResult!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        _seedResult!.startsWith('Errore') ||
                            _seedResult!.startsWith('Gruppo') ||
                            _seedResult!.startsWith('Giornata') ||
                            _seedResult!.startsWith('FirestoreService')
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
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
