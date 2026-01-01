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
  static const int _matchdayNumber = 20;

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

  int get _pickedCount => _matches.where((m) => !_pickFor(m.id).isNone).length;

  int get _missingCount => _matches.length - _pickedCount;

  DateTime get _firstKickoff =>
      _matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime get _lockTime => _firstKickoff.subtract(const Duration(hours: 2));

  bool get _locked => DateTime.now().isAfter(_lockTime);

  String get _matchdayLabel {
    final daysLabel = formatMatchdayDaysItalian(_matches.map((m) => m.kickoff));
    return 'giornata $_matchdayNumber - $daysLabel';
  }

  double? _oddsForPick(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.none:
        return null;
      case PickOption.home:
        return match.odds.home;
      case PickOption.draw:
        return match.odds.draw;
      case PickOption.away:
        return match.odds.away;
      case PickOption.homeDraw:
        return match.odds.homeDraw;
      case PickOption.drawAway:
        return match.odds.drawAway;
      case PickOption.homeAway:
        return match.odds.homeAway;
    }
  }

  double? get _averageOddsPlayed {
    final values = <double>[];
    for (final match in _matches) {
      final pick = _pickFor(match.id);
      final odds = _oddsForPick(match, pick);
      if (odds != null) values.add(odds);
    }
    if (values.isEmpty) return null;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  void _setPick(String matchId, PickOption pick) {
    setState(() => _picks[matchId] = pick);
  }

  void _clearPick(String matchId) {
    setState(() => _picks.remove(matchId));
  }

  Future<bool> _confirmSubmitIfMissing(int missing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Attenzione'),
          content: Text(
            'Hai lasciato $missing partite senza pronostico.\n\n'
            'Regola Cassandra: per ogni partita non giocata verrà applicata '
            'una penalità pari a -quota più alta (tra 1/X/2) in fase di calcolo.\n\n'
            'Vuoi inviare comunque?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Invia comunque'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _submit(VisibilityChoice visibility) async {
    if (_locked) return;

    final missing = _missingCount;
    if (missing > 0) {
      final ok = await _confirmSubmitIfMissing(missing);
      if (!ok) return;
      if (!mounted) return; // dopo await
    }

    if (!mounted) return;
    setState(() {
      _submittedVisibility = visibility;
      _submittedAt = DateTime.now();
    });

    final label = visibility == VisibilityChoice.public
        ? 'pubblica'
        : 'privata';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Schedina inviata (visibilità: $label)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockLabel = _locked
        ? 'giocate bloccate'
        : 'modificabile fino alle ${formatKickoff(_lockTime)}';

    final avg = _averageOddsPlayed;
    final avgLabel = avg == null ? '-' : formatOdds(avg);

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
                      ButtonSegment(
                        value: 1,
                        label: Text('i pronostici passati'),
                      ),
                      ButtonSegment(
                        value: 0,
                        label: Text('i pronostici futuri'),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (newSelection) {
                      setState(() => _segment = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _matchdayLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(lockLabel, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    'scelte: $_pickedCount/${_matches.length}  •  quota media: $avgLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  if (_submittedVisibility != null && _submittedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'ultimo invio: ${formatKickoff(_submittedAt!)} '
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
                  ? const Center(
                      child: Text('Qui compariranno i pronostici passati'),
                    )
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
                  onPressed: _locked
                      ? null
                      : () => _submit(VisibilityChoice.private),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CassandraColors.primary),
                    foregroundColor: CassandraColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('invia senza mostrare'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _locked
                      ? null
                      : () => _submit(VisibilityChoice.public),
                  style: FilledButton.styleFrom(
                    backgroundColor: CassandraColors.primary,
                    foregroundColor: CassandraColors.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('invia e mostra'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
