import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../predictions_page.dart';
import '../models/formatters.dart';
import 'predictions_meta_chip.dart';

class PredictionsMatchdaySummary extends StatelessWidget {
  const PredictionsMatchdaySummary({
    super.key,
    required this.matchdayTitle,
    required this.matchdayRange,
    required this.lockLabel,
    required this.locked,
    required this.isOffline,
    required this.correctLine,
    required this.pointsLine,
    this.submittedVisibility,
    this.submittedAt,
  });

  final String matchdayTitle;
  final String matchdayRange;
  final String lockLabel;
  final bool locked;
  final bool isOffline;
  final String correctLine;
  final String pointsLine;
  final VisibilityChoice? submittedVisibility;
  final DateTime? submittedAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final matchdayHeaderStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(
          fontWeight: FontWeight.w700,
          color: CassandraColors.slate,
          fontSize:
              (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) + 2,
        );
    final summaryLineStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: CassandraColors.slate,
    );

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: CassandraColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(matchdayTitle, style: matchdayHeaderStyle),
            if (matchdayRange.isNotEmpty) ...[
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    matchdayRange,
                    maxLines: 1,
                    style: matchdayHeaderStyle,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (lockLabel.isNotEmpty)
                  Expanded(
                    child: PredictionsMetaChip(
                      icon: locked
                          ? Icons.lock_outline
                          : Icons.schedule_outlined,
                      label: lockLabel,
                      backgroundColor: locked
                          ? CassandraColors.primary.withValues(alpha: 0.13)
                          : CassandraColors.bg,
                      borderColor: locked
                          ? CassandraColors.primary.withValues(alpha: 0.35)
                          : CassandraColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
                if (isOffline && lockLabel.isNotEmpty) const SizedBox(width: 8),
                if (isOffline)
                  Flexible(
                    child: PredictionsMetaChip(
                      icon: Icons.wifi_off_outlined,
                      label: l10n.predictionsOfflineStatus,
                      backgroundColor: isOffline
                          ? CassandraColors.primary.withValues(alpha: 0.12)
                          : CassandraColors.bg,
                      borderColor: isOffline
                          ? CassandraColors.primary.withValues(alpha: 0.35)
                          : CassandraColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
              ],
            ),
            if (lockLabel.isNotEmpty || isOffline) const SizedBox(height: 8),
            Text(correctLine, style: summaryLineStyle),
            const SizedBox(height: 4),
            Text(pointsLine, style: summaryLineStyle),
            if (submittedVisibility != null && submittedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                l10n.predictionsLastSubmit(
                  formatKickoff(submittedAt!),
                  submittedVisibility == VisibilityChoice.public
                      ? l10n.predictionsVisibilityPublic
                      : l10n.predictionsVisibilityPrivate,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: CassandraColors.slate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
