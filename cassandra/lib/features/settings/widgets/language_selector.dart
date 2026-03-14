import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/theme/cassandra_colors.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    required this.currentValue,
    required this.onChanged,
  });

  final CassandraLanguage currentValue;
  final ValueChanged<CassandraLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.settingsLanguage,
          style: const TextStyle(
            color: CassandraColors.brightSnow,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CassandraLanguage>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: <ButtonSegment<CassandraLanguage>>[
            ButtonSegment(
              value: CassandraLanguage.system,
              label: Text(l10n.settingsLanguageSystem),
            ),
            ButtonSegment(
              value: CassandraLanguage.it,
              label: Text(l10n.settingsLanguageIt),
            ),
            ButtonSegment(
              value: CassandraLanguage.en,
              label: Text(l10n.settingsLanguageEn),
            ),
          ],
          selected: <CassandraLanguage>{currentValue},
          onSelectionChanged: (value) => onChanged(value.first),
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
