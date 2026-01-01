import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';

enum VisibilityChoice { private, public }

class PredictionsPage extends StatefulWidget {
  const PredictionsPage({super.key});

  @override
  State<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends State<PredictionsPage> {
  late final List<PredictionMatch> _matches;
  final Map<String, PickOption> _picks = {};

  int _segment = 0; // 0 = futuri, 1 = passati

  VisibilityChoice? _submittedVisibility;
  DateTime? _submittedAt;

  @override
  void initState() {
    super.initState();
    _matches = mockPredictionMatches();
  }

  PickOption _pickFor(String matchId) => _picks[matchId] ?? PickOption.none;

  DateTime get _firstKickoff {
    return _matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime get _lockTime => _firstKickoff.subtract(const Duration(hours: 2));

  bool get _locked => DateTime.now().isAfter(_lockTime);

  void _setPick(String matchId, PickOption pick) {
    setState(() {
      _picks[matchId] = pick;
    });
  }

  void _clearPick(String matchId) {
    setState(() {
      _picks.remove(matchId);
    });
  }

  void _submit(VisibilityChoice visibility) {
    setState(() {
      _submittedVisibility = visibility;
      _submittedAt = DateTime.now();
    });

    final label = visibility == VisibilityChoice.public ? 'pubblica' : 'privata';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Schedina inviata (visibilità: $label)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockLabel = _locked
        ? 'Giocate bloccate'
        : 'Modificabile fino alle ${formatKickoff(_lockTime)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Pronostici')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Futuri')),
                      ButtonSegment(value: 1, label: Text('Passati')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (newSelection) {
                      setState(() => _segment = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text('Giornata demo', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(lockLabel, style: Theme.of(context).textTheme.bodySmall),
                  if (_submittedVisibility != null && _submittedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ultimo invio: ${formatKickoff(_submittedAt!)} '
                      '(${_submittedVisibility == VisibilityChoice.public ? 'pubblica' : 'privata'})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CassandraColors.slate,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? const Center(child: Text('Qui compariranno i pronostici passati'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        final match = _matches[i];
                        final pick = _pickFor(match.id);

                        return PredictionMatchCard(
                          match: match,
                          pick: pick,
                          locked: _locked,
                          onPick: (p) => _setPick(match.id, p),
                          onClear: () => _clearPick(match.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _locked ? null : () => _submit(VisibilityChoice.private),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CassandraColors.primary),
                    foregroundColor: CassandraColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Invia senza mostrare'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _locked ? null : () => _submit(VisibilityChoice.public),
                  style: FilledButton.styleFrom(
                    backgroundColor: CassandraColors.primary,
                    foregroundColor: CassandraColors.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Invia e mostra'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
