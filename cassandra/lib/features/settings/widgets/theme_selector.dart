import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ThemeSelector extends StatelessWidget {
  const ThemeSelector({
    super.key,
    required this.currentValue,
    required this.onChanged,
  });

  final CassandraThemeMode currentValue;
  final ValueChanged<CassandraThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.settingsThemeMode,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<CassandraThemeMode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<CassandraThemeMode>>[
            ButtonSegment(
              value: CassandraThemeMode.system,
              label: Text(l10n.settingsThemeModeSystem),
            ),
            ButtonSegment(
              value: CassandraThemeMode.light,
              label: Text(l10n.settingsThemeModeLight),
            ),
            ButtonSegment(
              value: CassandraThemeMode.dark,
              label: Text(l10n.settingsThemeModeDark),
            ),
          ],
          selected: <CassandraThemeMode>{currentValue},
          onSelectionChanged: (value) => onChanged(value.first),
        ),
      ],
    );
  }
}
