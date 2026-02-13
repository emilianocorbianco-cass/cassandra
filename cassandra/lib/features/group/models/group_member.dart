class GroupMember {
  final String id;
  final String displayName;
  final String teamName;

  /// Seed per generare colore avatar in modo deterministico
  final int avatarSeed;

  /// Squadra del cuore (per badge 🦉)
  final String? favoriteTeam;

  const GroupMember({
    required this.id,
    required this.displayName,
    required this.teamName,
    required this.avatarSeed,
    this.favoriteTeam,
  });

  String get uiName {
    final team = teamName.trim();
    if (team.isNotEmpty) return team;
    final display = displayName.trim();
    if (display.isNotEmpty) return display;
    return 'Team';
  }

  String get avatarInitial {
    final name = uiName.trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }
}
