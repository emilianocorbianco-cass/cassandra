import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../app/theme/cassandra_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../models/badge_type.dart';

class AvatarWithBadges extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final double radius;
  final List<BadgeType> badges;
  final String? imagePathOrUrl;

  const AvatarWithBadges({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.badges,
    this.imagePathOrUrl,
    this.radius = 18,
  });

  @override
  State<AvatarWithBadges> createState() => _AvatarWithBadgesState();
}

class _AvatarWithBadgesState extends State<AvatarWithBadges> {
  String? _cachedSource;
  ImageProvider<Object>? _cachedProvider;

  static ImageProvider<Object>? _buildProvider(String? imagePathOrUrl) {
    final source = (imagePathOrUrl ?? '').trim();
    if (source.isEmpty) return null;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return NetworkImage(source);
    }
    if (source.startsWith('data:')) {
      try {
        final comma = source.indexOf(',');
        if (comma >= 0) {
          return MemoryImage(base64Decode(source.substring(comma + 1)));
        }
      } catch (_) {}
      return null;
    }
    final file = File(source);
    return file.existsSync() ? FileImage(file) : null;
  }

  @override
  void initState() {
    super.initState();
    _cachedSource = widget.imagePathOrUrl;
    _cachedProvider = _buildProvider(widget.imagePathOrUrl);
  }

  @override
  void didUpdateWidget(AvatarWithBadges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imagePathOrUrl != _cachedSource) {
      _cachedSource = widget.imagePathOrUrl;
      _cachedProvider = _buildProvider(widget.imagePathOrUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = AppLocalizations.of(context)!.localeName.startsWith('en');
    final sorted = widget.badges.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final visible = sorted.take(2).toList(); // per ora max 2 badge visibili

    final bubbleSize = (widget.radius * 0.75).clamp(12.0, 16.0);
    final imageProvider = _cachedProvider;

    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: widget.backgroundColor,
            foregroundImage: imageProvider,
            child: imageProvider == null
                ? Text(widget.text, style: const TextStyle(color: Colors.white))
                : null,
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
                        message: visible[i].title(english: isEnglish),
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
