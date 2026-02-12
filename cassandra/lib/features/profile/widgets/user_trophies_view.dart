import 'package:flutter/material.dart';

import '../../../app/state/app_settings.dart';
import '../../../app/state/app_state.dart';
import '../../../app/state/cassandra_scope.dart';
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

  bool _isEnglish(BuildContext context, AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  Widget _trophyTile(
    BuildContext context,
    BadgeType type,
    int count, {
    required bool en,
  }) {
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
            Text(type.title(english: en), textAlign: TextAlign.center),
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
    final app = CassandraScope.of(context);
    final en = _isEnglish(context, app);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                en
                    ? 'Trophies for ${member.displayName} (demo season history).\n'
                          'Rules: 👑 group winner • L last place • 👁️ 10/10 correct • 🦉 jinxed own favorite team.'
                    : 'Trofei di ${member.displayName} (storico stagione demo).\n'
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
                en: en,
              ),
              _trophyTile(
                context,
                BadgeType.eyes,
                trophies.of(BadgeType.eyes),
                en: en,
              ),
              _trophyTile(
                context,
                BadgeType.owl,
                trophies.of(BadgeType.owl),
                en: en,
              ),
              _trophyTile(
                context,
                BadgeType.loser,
                trophies.of(BadgeType.loser),
                en: en,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
