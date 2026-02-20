import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';

class PredictionsSubmitBar extends StatelessWidget {
  const PredictionsSubmitBar({
    super.key,
    required this.locked,
    required this.onSubmitPrivate,
    required this.onSubmitPublic,
  });

  final bool locked;
  final VoidCallback onSubmitPrivate;
  final VoidCallback onSubmitPublic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: CassandraColors.bg.withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(
              color: CassandraColors.primary.withValues(alpha: 0.14),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: CassandraColors.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: locked ? null : onSubmitPrivate,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: CassandraColors.primary.withValues(alpha: 0.65),
                    ),
                    foregroundColor: CassandraColors.primary,
                    backgroundColor: CassandraColors.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: Text(
                    l10n.predictionsSubmitWithoutShowing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: locked ? null : onSubmitPublic,
                  style: FilledButton.styleFrom(
                    backgroundColor: CassandraColors.primary,
                    foregroundColor: CassandraColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(
                    l10n.predictionsSubmitAndShow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
