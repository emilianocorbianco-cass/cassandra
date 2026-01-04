import 'dart:ui';

/// Lingua dell'app:
/// - system: segue la lingua del telefono
/// - it/en: forza l'app in IT o EN
enum CassandraLanguage { system, it, en }

CassandraLanguage cassandraLanguageFromStorage(String? value) {
  switch (value) {
    case 'it':
      return CassandraLanguage.it;
    case 'en':
      return CassandraLanguage.en;
    case 'system':
    default:
      return CassandraLanguage.system;
  }
}

String cassandraLanguageToStorage(CassandraLanguage value) {
  switch (value) {
    case CassandraLanguage.system:
      return 'system';
    case CassandraLanguage.it:
      return 'it';
    case CassandraLanguage.en:
      return 'en';
  }
}

Locale? localeForLanguage(CassandraLanguage value) {
  switch (value) {
    case CassandraLanguage.system:
      return null; // lascia decidere al sistema
    case CassandraLanguage.it:
      return const Locale('it');
    case CassandraLanguage.en:
      return const Locale('en');
  }
}

/// Chi può vedere i pronostici (di default) quando l'utente invia.
/// Nota: per ora è SOLO una preferenza; la useremo davvero quando collegheremo backend/regole.
enum PredictionVisibility { public, friends, private }

PredictionVisibility predictionVisibilityFromStorage(String? value) {
  switch (value) {
    case 'public':
      return PredictionVisibility.public;
    case 'friends':
      return PredictionVisibility.friends;
    case 'private':
      return PredictionVisibility.private;
    default:
      return PredictionVisibility.friends;
  }
}

String predictionVisibilityToStorage(PredictionVisibility value) {
  switch (value) {
    case PredictionVisibility.public:
      return 'public';
    case PredictionVisibility.friends:
      return 'friends';
    case PredictionVisibility.private:
      return 'private';
  }
}

String predictionVisibilityLabel(
  PredictionVisibility value, {
  required bool english,
}) {
  switch (value) {
    case PredictionVisibility.public:
      return english ? 'Public' : 'Pubblico';
    case PredictionVisibility.friends:
      return english ? 'Friends' : 'Amici';
    case PredictionVisibility.private:
      return english ? 'Private' : 'Privato';
  }
}
