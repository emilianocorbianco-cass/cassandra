import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';

class PredictionsMetaChip extends StatelessWidget {
  const PredictionsMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.backgroundColor,
    this.borderColor,
  });

  final IconData icon;
  final String label;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? CassandraColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                borderColor ?? CassandraColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: CassandraColors.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: CassandraColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
