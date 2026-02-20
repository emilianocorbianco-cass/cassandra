import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';

class GroupEmptyView extends StatelessWidget {
  const GroupEmptyView({
    super.key,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCreateGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: CassandraColors.primary,
                    foregroundColor: CassandraColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(l10n.groupEmptyCreateButton),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onJoinGroup,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(l10n.groupEmptyJoinButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
