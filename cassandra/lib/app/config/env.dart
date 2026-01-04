import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String? get apiFootballKey {
    final v = dotenv.env['API_FOOTBALL_KEY'];
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static bool get useRapidApi {
    final v = (dotenv.env['API_FOOTBALL_USE_RAPIDAPI'] ?? 'false')
        .trim()
        .toLowerCase();
    return v == 'true' || v == '1' || v == 'yes';
  }

  static String get baseUrl {
    final v = dotenv.env['API_FOOTBALL_BASE_URL'];
    if (v == null || v.trim().isEmpty) {
      return 'https://v3.football.api-sports.io';
    }
    return v.trim();
  }

  static String get rapidApiHost {
    final v = dotenv.env['API_FOOTBALL_RAPIDAPI_HOST'];
    if (v == null || v.trim().isEmpty) {
      return 'v3.football.api-sports.io';
    }
    return v.trim();
  }
}
