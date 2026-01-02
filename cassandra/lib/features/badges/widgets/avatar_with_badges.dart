import 'package:flutter/material.dart';
import '../../../app/theme/cassandra_colors.dart';
import '../models/badge_type.dart';

class AvatarWithBadges extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final double radius;
  final List<BadgeType> badges;

  const AvatarWithBadges({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.badges,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = badges.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final visible = sorted.take(2).toList(); // per ora max 2 badge visibili

    final bubbleSize = (radius * 0.75).clamp(12.0, 16.0);

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
          if (visible.isNotEmpty)
            Positioned(
              top: 2,
              left: 2,
              right: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (int i = 0; i < visible.length; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                      child: Tooltip(
                        message: visible[i].titleIt,
                        child: _BadgeBubble(type: visible[i], size: bubbleSize),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeBubble extends StatelessWidget {
  final BadgeType type;
  final double size;

  const _BadgeBubble({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (type) {
      case BadgeType.crown:
        child = Icon(
          Icons.workspace_premium,
          size: size * 0.7,
          color: CassandraColors.bg,
        );
        break;
      case BadgeType.eyes:
        child = Icon(
          Icons.remove_red_eye,
          size: size * 0.7,
          color: CassandraColors.bg,
        );
        break;
      case BadgeType.owl:
        child = Text('🦉', style: TextStyle(fontSize: size * 0.7));
        break;
      case BadgeType.loser:
        child = Text(
          'L',
          style: TextStyle(
            fontSize: size * 0.75,
            fontWeight: FontWeight.w800,
            color: CassandraColors.bg,
          ),
        );
        break;
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CassandraColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: CassandraColors.bg, width: 1),
      ),
      child: child,
    );
  }
}
