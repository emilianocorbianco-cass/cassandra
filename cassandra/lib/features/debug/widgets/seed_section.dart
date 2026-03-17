import 'package:flutter/material.dart';

import '../cold_test_service.dart';

class SeedSection extends StatefulWidget {
  final ValueChanged<int>? onSeeded;

  const SeedSection({super.key, this.onSeeded});

  @override
  State<SeedSection> createState() => _SeedSectionState();
}

class _SeedSectionState extends State<SeedSection> {
  final _service = ColdTestService();
  int _dayNumber = 1;
  double _kickoffInterval = 10;
  double _matchDuration = 12;
  bool _loading = false;
  String? _resultMessage;
  bool _success = false;

  int get _estimatedMinutes {
    final totalMatchTime =
        (10 - 1) * _kickoffInterval.round() + _matchDuration.round();
    return 20 + totalMatchTime; // 20 min prep + match time
  }

  String get _estimatedTimeLabel {
    final mins = _estimatedMinutes;
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  Future<void> _seed() async {
    setState(() {
      _loading = true;
      _resultMessage = null;
    });

    try {
      final result = await _service.seedMatchday(
        dayNumber: _dayNumber,
        kickoffIntervalMin: _kickoffInterval.round(),
        matchDurationMin: _matchDuration.round(),
      );
      if (!mounted) return;

      final lockTime = result['lockTime'] as String? ?? '';
      final matchCount = result['matchCount'] as int? ?? 0;

      setState(() {
        _loading = false;
        _success = true;
        _resultMessage =
            'Giornata $_dayNumber preparata: $matchCount partite.\n'
            'Lock: $lockTime';
      });

      widget.onSeeded?.call(_dayNumber);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _resultMessage = 'Errore: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seed Giornata',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.orange.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Giornata: ', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _dayNumber,
              items: List.generate(
                38,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}'),
                ),
              ),
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _dayNumber = v ?? 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Intervallo kickoff: ${_kickoffInterval.round()} min',
          style: const TextStyle(fontSize: 13),
        ),
        Slider(
          value: _kickoffInterval,
          min: 3,
          max: 15,
          divisions: 12,
          label: '${_kickoffInterval.round()} min',
          onChanged:
              _loading ? null : (v) => setState(() => _kickoffInterval = v),
        ),
        Text(
          'Durata partita: ${_matchDuration.round()} min',
          style: const TextStyle(fontSize: 13),
        ),
        Slider(
          value: _matchDuration,
          min: 5,
          max: 15,
          divisions: 10,
          label: '${_matchDuration.round()} min',
          onChanged:
              _loading ? null : (v) => setState(() => _matchDuration = v),
        ),
        const SizedBox(height: 4),
        Text(
          'Durata stimata: $_estimatedTimeLabel',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: _loading ? null : _seed,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              _loading
                  ? 'Preparazione...'
                  : 'Prepara Giornata $_dayNumber',
            ),
          ),
        ),
        if (_resultMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _resultMessage!,
            style: TextStyle(
              color: _success ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
