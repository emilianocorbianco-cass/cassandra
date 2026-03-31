import 'package:flutter/material.dart';

import '../../app/navigation/home_shell.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/firestore/models/group_document.dart';
import '../profile/widgets/profile_image_picker.dart';
import 'create_group_page.dart';
import 'join_group_page.dart';
import 'widgets/group_image_picker.dart';

/// Full-screen hub shown after login when the user belongs to 2+ groups.
/// Displays the user's profile, create/join buttons, and a list of groups
/// to choose from.
class GroupHubPage extends StatefulWidget {
  const GroupHubPage({super.key});

  @override
  State<GroupHubPage> createState() => _GroupHubPageState();
}

class _GroupHubPageState extends State<GroupHubPage> {
  Future<List<GroupDocument>>? _groupsFuture;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _loadGroups();
  }

  void _loadGroups() {
    final app = CassandraScope.of(context);
    final fs = app.firestoreService;
    final ids = app.firestoreGroupIds;
    if (fs != null && ids.isNotEmpty) {
      _groupsFuture = fs.getGroups(ids);
    } else {
      _groupsFuture = Future.value(const []);
    }
  }

  void _refreshGroups() {
    setState(_loadGroups);
  }

  void _selectGroup(String groupId) {
    final app = CassandraScope.of(context);
    // setActiveGroupId already triggers refreshActiveGroupMetadataFromFirestore
    // and history hydration in the background.
    app.setActiveGroupId(groupId);

    // If HomeShell is below us (came from swipe), just pop back to it.
    // Otherwise (came from splash), replace this route with HomeShell.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  void _openCreateGroup() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateGroupPage(
          onGroupCreated: () {
            if (!mounted) return;
            final app = CassandraScope.of(context);
            // If only 1 group now, go directly to HomeShell
            if (app.firestoreGroupIds.length <= 1) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeShell()),
                (route) => false,
              );
            } else {
              // Pop back to hub and refresh
              Navigator.of(context, rootNavigator: true).pop();
              _refreshGroups();
            }
          },
        ),
      ),
    );
  }

  void _openJoinGroup() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => JoinGroupPage(
          onJoined: () {
            if (!mounted) return;
            final app = CassandraScope.of(context);
            if (app.firestoreGroupIds.length <= 1) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeShell()),
                (route) => false,
              );
            } else {
              Navigator.of(context, rootNavigator: true).pop();
              _refreshGroups();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    final rawHandle = app.profile.teamName.trim();
    final handle = rawHandle.isEmpty
        ? '@cassandra'
        : (rawHandle.startsWith('@') ? rawHandle : '@$rawHandle');

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // ── Profile section ──
              ProfileImageDisplay(
                imagePathOrUrl: app.profile.photoUrl,
                radius: 65,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.welcomeBackTitle(handle),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: CassandraColors.brightSnow,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // ── Create / Join buttons ──
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openCreateGroup,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: CassandraColors.charcoal,
                          foregroundColor: CassandraColors.brightSnow,
                          side: const BorderSide(color: CassandraColors.brightSnow),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          l10n.groupHubCreateGroup,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openJoinGroup,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: CassandraColors.charcoal,
                          foregroundColor: CassandraColors.brightSnow,
                          side: const BorderSide(color: CassandraColors.brightSnow),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          l10n.groupHubJoinGroup,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Separator ──
              const Divider(color: CassandraColors.brightSnow, thickness: 0.5, height: 0.5),
              // ── Group list ──
              Expanded(
                child: ClipRect(
                  child: FutureBuilder<List<GroupDocument>>(
                    future: _groupsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final groups = snapshot.data ?? const [];
                      if (groups.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(top: 18),
                        clipBehavior: Clip.none,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return _GroupCard(
                            group: group,
                            onTap: () => _selectGroup(group.id),
                          );
                        },
                      );
                    },
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final GroupDocument group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: CassandraColors.platinum,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              GroupImageDisplay(
                imagePath: group.imageUrl,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            style: const TextStyle(
                              color: CassandraColors.inkBlack,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.groupHubMemberCount(group.memberCount),
                      style: TextStyle(
                        color: CassandraColors.inkBlack.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: CassandraColors.inkBlack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
