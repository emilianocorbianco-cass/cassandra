import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';
import 'group_image_picker.dart';

class GroupHeaderSection extends StatelessWidget {
  const GroupHeaderSection({
    super.key,
    required this.groupName,
    this.groupImagePath,
    required this.matchdayLabel,
    required this.resultsLabel,
    required this.segment,
    required this.onSegmentChanged,
  });

  final String groupName;
  final String? groupImagePath;
  final String matchdayLabel;
  final String resultsLabel;
  final int segment;
  final ValueChanged<int> onSegmentChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GroupImageDisplay(imagePath: groupImagePath, radius: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      matchdayLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            resultsLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CassandraColors.slate),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(l10n.groupStandings)),
              ButtonSegment(value: 1, label: Text(l10n.groupMatchdays)),
              ButtonSegment(value: 2, label: Text(l10n.groupStats)),
            ],
            selected: {segment},
            onSelectionChanged: (s) => onSegmentChanged(s.first),
          ),
        ],
      ),
    );
  }
}
