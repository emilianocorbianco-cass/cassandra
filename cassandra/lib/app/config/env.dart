import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  /// Lettura "safe" delle variabili.
  /// In widget test, dotenv non è inizializzato e dotenv.env lancia NotInitializedError:
  /// qui lo trasformiamo in null.
  static String? _raw(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  static String? _trimmed(String key) {
    final v = _raw(key);
    if (v == null) return null;
    final t = v.trim();
    if (t.isEmpty) return null;
    return t;
  }

  static String? get apiFootballKey => _trimmed('API_FOOTBALL_KEY');

  static bool get useRapidApi {
    final v = (_raw('API_FOOTBALL_USE_RAPIDAPI') ?? 'false')
        .trim()
        .toLowerCase();
    return v == 'true' || v == '1' || v == 'yes';
  }

  static String get baseUrl {
    final v = _trimmed('API_FOOTBALL_BASE_URL');
    if (v == null) {
      return 'https://v3.football.api-sports.io';
    }
    return v;
  }

  static String get rapidApiHost {
    final v = _trimmed('API_FOOTBALL_RAPIDAPI_HOST');
    if (v == null) {
      return 'v3.football.api-sports.io';
    }
    return v;
  }
}
