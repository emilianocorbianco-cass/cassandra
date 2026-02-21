import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class Env {
  static bool _missingApiFootballKeyLogged = false;

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

  static String? get apiFootballKey {
    final key = _trimmed('API_FOOTBALL_KEY');
    if (key == null && !_missingApiFootballKeyLogged) {
      _missingApiFootballKeyLogged = true;
      if (kDebugMode) {
        debugPrint(
          '[env] API_FOOTBALL_KEY missing: app will fallback to cached/demo data.',
        );
      }
    }
    return key;
  }

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
