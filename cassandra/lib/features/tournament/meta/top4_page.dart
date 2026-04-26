import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';

/// Page for predicting the World Cup top 4 (semifinals).
///
/// Shows a pool of qualified teams. The user taps to select exactly 4.
/// Scoring: 0 correct = 0, 1 = 2, 2 = 5, 3 = 10, 4 = 20 points.
class Top4Page extends StatefulWidget {
  const Top4Page({
    super.key,
    required this.tournamentId,
    required this.teamPool,
    this.initialPicks,
    required this.onSave,
  });

  final String tournamentId;

  /// All teams available for selection (e.g. 32 qualified teams).
  final List<String> teamPool;

  /// Previously saved picks (up to 4).
  final List<String>? initialPicks;

  final ValueChanged<List<String>> onSave;

  @override
  State<Top4Page> createState() => _Top4PageState();
}

class _Top4PageState extends State<Top4Page> {
  late Set<String> _selected;
  bool _saved = false;

  static const int _maxPicks = 4;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initialPicks ?? const []);
  }

  void _toggleTeam(String team) {
    setState(() {
      if (_selected.contains(team)) {
        _selected.remove(team);
      } else if (_selected.length < _maxPicks) {
        _selected.add(team);
      }
      _saved = false;
    });
  }

  void _save() {
    if (_selected.length != _maxPicks) {
      final en = Localizations.localeOf(context)
          .languageCode
          .toLowerCase()
          .startsWith('en');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            en
                ? 'Select exactly $_maxPicks teams'
                : 'Seleziona esattamente $_maxPicks squadre',
          ),
        ),
      );
      return;
    }
    widget.onSave(_selected.toList());
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prime 4 salvate')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('en');

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      appBar: AppBar(
        title: Text(en ? 'Top 4' : 'Prime 4'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              en ? 'Save' : 'Salva',
              style: TextStyle(
                color: _saved
                    ? CassandraColors.brightSnow.withValues(alpha: 0.5)
                    : CassandraColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Selection counter
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Row(
              children: [
                Text(
                  en ? 'Selected' : 'Selezionate',
                  style: const TextStyle(
                    color: CassandraColors.brightSnow,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _selected.length == _maxPicks
                        ? CassandraColors.primary
                        : CassandraColors.charcoal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selected.length}/$_maxPicks',
                    style: const TextStyle(
                      color: CassandraColors.brightSnow,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                // Scoring info
                Text(
                  '0→0  1→2  2→5  3→10  4→20',
                  style: TextStyle(
                    color: CassandraColors.brightSnow.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Selected chips
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final team in _selected)
                    Chip(
                      label: Text(
                        team,
                        style: const TextStyle(
                          color: CassandraColors.brightSnow,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: CassandraColors.primary,
                      deleteIcon: const Icon(
                        Icons.close,
                        size: 16,
                        color: CassandraColors.brightSnow,
                      ),
                      onDeleted: () => _toggleTeam(team),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Divider(
            color: CassandraColors.charcoal,
            height: 1,
            indent: 18,
            endIndent: 18,
          ),
          // Team grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.2,
              ),
              itemCount: widget.teamPool.length,
              itemBuilder: (context, index) {
                final team = widget.teamPool[index];
                final isSelected = _selected.contains(team);
                final canSelect =
                    isSelected || _selected.length < _maxPicks;

                return Material(
                  color: isSelected
                      ? CassandraColors.primary
                      : CassandraColors.platinum,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: canSelect ? () => _toggleTeam(team) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        team,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? CassandraColors.brightSnow
                              : canSelect
                                  ? CassandraColors.inkBlack
                                  : CassandraColors.inkBlack
                                      .withValues(alpha: 0.3),
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
