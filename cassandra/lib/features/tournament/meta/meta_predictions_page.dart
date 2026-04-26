import 'package:flutter/material.dart';

import '../../../app/state/cassandra_scope.dart';
import '../../../app/theme/cassandra_colors.dart';
import '../../../services/firestore/models/meta_prediction_document.dart';
import 'group_order_page.dart';
import 'top4_page.dart';

/// Hub page for tournament meta-predictions.
///
/// Shows cards for each available meta-prediction type
/// (group order, top 4, etc.) with status indicators.
class MetaPredictionsPage extends StatefulWidget {
  const MetaPredictionsPage({super.key});

  @override
  State<MetaPredictionsPage> createState() => _MetaPredictionsPageState();
}

class _MetaPredictionsPageState extends State<MetaPredictionsPage> {
  MetaPredictionDocument? _doc;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    final doc = await fs.getMetaPredictions(
      uid: app.profile.id,
      tournamentId: app.activeTournament.id,
    );
    if (mounted) setState(() => _doc = doc);
  }

  Future<void> _saveGroupOrder(Map<String, List<String>> picks) async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    final doc = MetaPredictionDocument(
      docId: '${app.profile.id}_${app.activeTournament.id}',
      uid: app.profile.id,
      tournamentId: app.activeTournament.id,
      groupOrderPicks: picks,
      top4Picks: _doc?.top4Picks,
    );
    await fs.saveMetaPredictions(
      uid: app.profile.id,
      tournamentId: app.activeTournament.id,
      doc: doc,
    );
    if (mounted) setState(() => _doc = doc);
  }

  Future<void> _saveTop4(List<String> picks) async {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    if (fs == null || !app.isAuthenticated) return;
    final doc = MetaPredictionDocument(
      docId: '${app.profile.id}_${app.activeTournament.id}',
      uid: app.profile.id,
      tournamentId: app.activeTournament.id,
      groupOrderPicks: _doc?.groupOrderPicks,
      top4Picks: picks,
    );
    await fs.saveMetaPredictions(
      uid: app.profile.id,
      tournamentId: app.activeTournament.id,
      doc: doc,
    );
    if (mounted) setState(() => _doc = doc);
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final en = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('en');
    final tournament = app.activeTournament;

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      appBar: AppBar(
        title: Text(en ? 'Meta-Predictions' : 'Meta-Pronostici'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
        children: [
          Text(
            tournament.displayName,
            style: const TextStyle(
              color: CassandraColors.brightSnow,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          // Group order card
          _MetaCard(
            title: en ? 'Group Order' : 'Ordine Gironi',
            subtitle: en
                ? '12 groups × 4 teams — max 48 pts'
                : '12 gironi × 4 squadre — max 48 pt',
            completed: _doc?.groupOrderPicks != null,
            points: _doc?.scoreCache?.groupOrderPoints,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupOrderPage(
                    tournamentId: tournament.id,
                    initialPicks: _doc?.groupOrderPicks,
                    onSave: _saveGroupOrder,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Top 4 card
          _MetaCard(
            title: en ? 'Top 4' : 'Prime 4',
            subtitle: en
                ? '0→0  1→2  2→5  3→10  4→20 pts'
                : '0→0  1→2  2→5  3→10  4→20 pt',
            completed: _doc?.top4Picks != null &&
                (_doc?.top4Picks?.length ?? 0) == 4,
            points: _doc?.scoreCache?.top4Points,
            onTap: () {
              // TODO: populate teamPool from qualified teams.
              final teamPool = <String>[
                for (var i = 1; i <= 48; i++) 'Team $i',
              ];
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Top4Page(
                    tournamentId: tournament.id,
                    teamPool: teamPool,
                    initialPicks: _doc?.top4Picks,
                    onSave: _saveTop4,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.title,
    required this.subtitle,
    required this.completed,
    this.points,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool completed;
  final int? points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CassandraColors.platinum,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: completed
                      ? CassandraColors.primary
                      : CassandraColors.charcoal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  completed ? Icons.check : Icons.edit,
                  color: CassandraColors.brightSnow,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: CassandraColors.inkBlack,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: CassandraColors.inkBlack.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (points != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CassandraColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$points pt',
                    style: const TextStyle(
                      color: CassandraColors.brightSnow,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: CassandraColors.inkBlack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
