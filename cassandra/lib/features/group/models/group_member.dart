class GroupMember {
  final String id;
  final String displayName;
  final String teamName;

  /// Seed per generare colore avatar in modo deterministico
  final int avatarSeed;

  const GroupMember({
    required this.id,
    required this.displayName,
    required this.teamName,
    required this.avatarSeed,
  });
}
