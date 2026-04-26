import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';

/// Page for predicting the finishing order of World Cup groups.
///
/// Shows 12 expandable group cards (A–L). Each card contains 4 teams
/// that the user can reorder by dragging.
class GroupOrderPage extends StatefulWidget {
  const GroupOrderPage({
    super.key,
    required this.tournamentId,
    this.initialPicks,
    required this.onSave,
  });

  final String tournamentId;
  final Map<String, List<String>>? initialPicks;
  final ValueChanged<Map<String, List<String>>> onSave;

  @override
  State<GroupOrderPage> createState() => _GroupOrderPageState();
}

class _GroupOrderPageState extends State<GroupOrderPage> {
  /// Group ID → ordered list of team names.
  late Map<String, List<String>> _picks;
  String? _expandedGroupId;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _picks = _buildInitialPicks();
  }

  Map<String, List<String>> _buildInitialPicks() {
    final initial = widget.initialPicks;
    if (initial != null && initial.isNotEmpty) {
      return {for (final e in initial.entries) e.key: List<String>.of(e.value)};
    }
    // Default: 12 groups with placeholder teams (will be replaced with real data).
    return {
      for (var i = 0; i < 12; i++)
        String.fromCharCode(65 + i): [
          'Squadra ${i * 4 + 1}',
          'Squadra ${i * 4 + 2}',
          'Squadra ${i * 4 + 3}',
          'Squadra ${i * 4 + 4}',
        ],
    };
  }

  void _onReorder(String groupId, int oldIndex, int newIndex) {
    setState(() {
      final list = _picks[groupId]!;
      if (newIndex > oldIndex) newIndex--;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      _saved = false;
    });
  }

  void _save() {
    widget.onSave(_picks);
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ordine gironi salvato')),
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
        title: Text(en ? 'Group Order' : 'Ordine Gironi'),
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
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
        itemCount: _picks.length,
        itemBuilder: (context, index) {
          final groupId = _picks.keys.elementAt(index);
          final teams = _picks[groupId]!;
          final expanded = _expandedGroupId == groupId;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _GroupCard(
              groupId: groupId,
              teams: teams,
              expanded: expanded,
              onToggle: () {
                setState(() {
                  _expandedGroupId = expanded ? null : groupId;
                });
              },
              onReorder: (oldIndex, newIndex) =>
                  _onReorder(groupId, oldIndex, newIndex),
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.groupId,
    required this.teams,
    required this.expanded,
    required this.onToggle,
    required this.onReorder,
  });

  final String groupId;
  final List<String> teams;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CassandraColors.platinum,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: expanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(
                    'Gruppo $groupId',
                    style: const TextStyle(
                      color: CassandraColors.inkBlack,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  // Preview: show first and last team
                  if (!expanded)
                    Text(
                      '${teams.first} → ${teams.last}',
                      style: TextStyle(
                        color: CassandraColors.inkBlack.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: CassandraColors.inkBlack,
                  ),
                ],
              ),
            ),
          ),
          // Reorderable team list
          if (expanded)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: teams.length,
              onReorder: onReorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: CassandraColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  elevation: 4,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                return _TeamRow(
                  key: ValueKey('${groupId}_${teams[index]}'),
                  position: index + 1,
                  teamName: teams[index],
                  index: index,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    super.key,
    required this.position,
    required this.teamName,
    required this.index,
  });

  final int position;
  final String teamName;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Position number
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: position <= 2
                  ? CassandraColors.primary
                  : CassandraColors.charcoal,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$position',
              style: const TextStyle(
                color: CassandraColors.brightSnow,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Team name
          Expanded(
            child: Text(
              teamName,
              style: const TextStyle(
                color: CassandraColors.inkBlack,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: const Icon(
              Icons.drag_handle,
              color: CassandraColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}
