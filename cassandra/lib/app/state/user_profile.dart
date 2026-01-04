class UserProfile {
  final String id;
  final String displayName;

  /// Nome squadra/handle
  final String teamName;

  /// Squadra del cuore (opzionale)
  final String? favoriteTeam;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.teamName,
    this.favoriteTeam,
  });

  UserProfile copyWith({
    String? teamName,
    String? favoriteTeam,
    bool clearFavoriteTeam = false,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName,
      teamName: teamName ?? this.teamName,
      favoriteTeam: clearFavoriteTeam
          ? null
          : (favoriteTeam ?? this.favoriteTeam),
    );
  }
}
