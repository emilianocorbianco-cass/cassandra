import 'package:flutter/material.dart';
import '../../../app/theme/cassandra_colors.dart';
import '../models/formatters.dart';

class OddsButton extends StatelessWidget {
  final String label;
  final double odds;
  final bool selected;
  final bool locked;
  final VoidCallback onPressed;

  const OddsButton({
    super.key,
    required this.label,
    required this.odds,
    required this.selected,
    required this.locked,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveFg = locked
        ? CassandraColors.primary.withValues(alpha: 0.42)
        : CassandraColors.primary;
    final fg = selected ? CassandraColors.onPrimary : inactiveFg;
    final bg = selected ? CassandraColors.primary : Colors.transparent;
    final sideColor = selected
        ? CassandraColors.primary
        : CassandraColors.primary.withValues(alpha: locked ? 0.45 : 0.8);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: locked ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            backgroundColor: bg,
            disabledForegroundColor: fg,
            disabledBackgroundColor: bg,
            side: BorderSide(color: sideColor, width: selected ? 2 : 1.2),
            padding: const EdgeInsets.symmetric(vertical: 10),
            elevation: selected ? 1 : 0,
            shadowColor: CassandraColors.primary.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: selected ? 0.2 : 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatOdds(odds),
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
