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
    final fg = selected ? CassandraColors.bg : CassandraColors.primary;
    final bg = selected ? CassandraColors.primary : Colors.transparent;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: locked ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            backgroundColor: bg,
            side: const BorderSide(color: CassandraColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(formatOdds(odds), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
