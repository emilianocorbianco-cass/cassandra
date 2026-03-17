import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import 'cold_test_service.dart';
import 'widgets/match_monitor_card.dart';
import 'widgets/seed_section.dart';
import 'widgets/wipe_section.dart';

class ColdTestPage extends StatefulWidget {
  const ColdTestPage({super.key});

  @override
  State<ColdTestPage> createState() => _ColdTestPageState();
}

class _ColdTestPageState extends State<ColdTestPage> {
  final _service = ColdTestService();
  int? _activeDayNumber;
  bool _autoResolve = false;
  bool _paused = false;
  Timer? _resolveTimer;
  int _secondsUntilNext = 60;
  Timer? _countdownTimer;

  // Resolve status
  int _revealed = 0;
  int _pending = 0;
  bool _finalized = false;
  String? _resolveError;

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onSeeded(int dayNumber) {
    setState(() {
      _activeDayNumber = dayNumber;
      _revealed = 0;
      _pending = 0;
      _finalized = false;
      _resolveError = null;
    });
  }

  void _toggleAutoResolve(bool value) {
    setState(() {
      _autoResolve = value;
      _paused = false;
    });

    if (value) {
      _startResolveLoop();
    } else {
      _stopResolveLoop();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _resolveTimer?.cancel();
      _countdownTimer?.cancel();
    } else {
      _callResolve();
      _startResolveLoop();
    }
  }

  void _startResolveLoop() {
    _resolveTimer?.cancel();
    _countdownTimer?.cancel();

    _secondsUntilNext = 60;
    _callResolve();

    _resolveTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_paused && _autoResolve && !_finalized) {
        _secondsUntilNext = 60;
        _callResolve();
      }
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_paused) {
        setState(() {
          _secondsUntilNext =
              (_secondsUntilNext - 1).clamp(0, 60);
        });
      }
    });
  }

  void _stopResolveLoop() {
    _resolveTimer?.cancel();
    _countdownTimer?.cancel();
  }

  Future<void> _callResolve() async {
    if (_activeDayNumber == null || _finalized) return;

    try {
      final result = await _service.resolveMatches(
        dayNumber: _activeDayNumber!,
      );
      if (!mounted) return;
      setState(() {
        _revealed = (result['revealed'] as num?)?.toInt() ?? 0;
        _pending = (result['pending'] as num?)?.toInt() ?? 0;
        _finalized = result['finalized'] as bool? ?? false;
        _resolveError = null;
      });

      if (_finalized) {
        _stopResolveLoop();
        setState(() => _autoResolve = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolveError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final seasonKey = app.currentSeasonKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cold Test'),
        backgroundColor: Colors.orange.shade50,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Wipe Section ──
          const WipeSection(),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Seed Section ──
          SeedSection(onSeeded: _onSeeded),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Auto-Resolve Section ──
          if (_activeDayNumber != null) ...[
            _buildAutoResolveSection(),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── Match Monitor ──
            _buildMatchMonitor(seasonKey),
            const SizedBox(height: 24),

            // ── Score Summary ──
            if (_finalized) _buildScoreSummary(),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildAutoResolveSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Auto-Resolve',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _autoResolve
                    ? _paused
                        ? 'In pausa'
                        : 'Attivo — prossimo check: ${_secondsUntilNext}s'
                    : 'Disattivo',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_autoResolve && !_finalized)
              IconButton(
                icon: Icon(
                  _paused ? Icons.play_arrow : Icons.pause,
                  color: Colors.blue.shade700,
                ),
                onPressed: _togglePause,
                tooltip: _paused ? 'Riprendi' : 'Pausa',
              ),
            Switch(
              value: _autoResolve,
              onChanged: _finalized ? null : _toggleAutoResolve,
              activeColor: Colors.blue.shade700,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _statusChip(
              'Rivelate: $_revealed',
              Colors.green.shade100,
              Colors.green.shade700,
            ),
            const SizedBox(width: 8),
            _statusChip(
              'In attesa: $_pending',
              Colors.orange.shade100,
              Colors.orange.shade700,
            ),
            if (_finalized) ...[
              const SizedBox(width: 8),
              _statusChip(
                'Completata',
                Colors.blue.shade100,
                Colors.blue.shade700,
              ),
            ],
          ],
        ),
        if (_resolveError != null) ...[
          const SizedBox(height: 8),
          Text(
            _resolveError!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildMatchMonitor(String seasonKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monitor Partite — Giornata $_activeDayNumber',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('seasons')
              .doc(seasonKey)
              .collection('matchdays')
              .doc(_activeDayNumber.toString())
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text(
                'Nessun dato disponibile.',
                style: TextStyle(fontSize: 13),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final matches = (data['matches'] as List<dynamic>?) ?? [];
            final outcomes =
                (data['outcomesByMatchId'] as Map<String, dynamic>?) ?? {};

            if (matches.isEmpty) {
              return const Text(
                'Nessuna partita trovata.',
                style: TextStyle(fontSize: 13),
              );
            }

            return Column(
              children: matches.map((m) {
                final match = m as Map<String, dynamic>;
                final matchId = match['id'] as String? ?? '';
                final outcome = outcomes[matchId] as String?;
                return MatchMonitorCard(match: match, outcome: outcome);
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildScoreSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Giornata $_activeDayNumber completata!',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tutti i risultati sono stati rivelati e i punteggi calcolati.\n'
            'Controlla la Leaderboard per vedere la classifica.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
