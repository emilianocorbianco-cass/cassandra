import 'package:flutter/material.dart';

import '../../badges/models/badge_counts.dart';
import '../../badges/models/badge_type.dart';
import '../../group/models/group_member.dart';

class UserTrophiesView extends StatelessWidget {
  final GroupMember member;
  final BadgeCounts trophies;

  const UserTrophiesView({
    super.key,
    required this.member,
    required this.trophies,
  });

  Widget _trophyTile(BuildContext context, BadgeType type, int count) {
    Widget icon;
    switch (type) {
      case BadgeType.crown:
        icon = const Icon(Icons.workspace_premium, size: 28);
        break;
      case BadgeType.eyes:
        icon = const Icon(Icons.remove_red_eye, size: 28);
        break;
      case BadgeType.owl:
        icon = const Text('🦉', style: TextStyle(fontSize: 26));
        break;
      case BadgeType.loser:
        icon = const Text(
          'L',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        );
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 10),
            Text(type.titleIt, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Trofei di ${member.displayName} (storico stagione demo).\n'
                'Regole: 👑 primo del gruppo • L ultimo • 👁️ 10/10 esatti • 🦉 gufata sulla squadra del cuore.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _trophyTile(
                context,
                BadgeType.crown,
                trophies.of(BadgeType.crown),
              ),
              _trophyTile(context, BadgeType.eyes, trophies.of(BadgeType.eyes)),
              _trophyTile(context, BadgeType.owl, trophies.of(BadgeType.owl)),
              _trophyTile(
                context,
                BadgeType.loser,
                trophies.of(BadgeType.loser),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
