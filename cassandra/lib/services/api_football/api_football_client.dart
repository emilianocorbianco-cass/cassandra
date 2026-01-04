import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_football_exceptions.dart';

class ApiFootballClient {
  ApiFootballClient({
    required this.apiKey,
    this.baseUrl = 'https://v3.football.api-sports.io',
    this.useRapidApi = false,
    this.rapidApiHost = 'v3.football.api-sports.io',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final bool useRapidApi;
  final String rapidApiHost;

  final http.Client _http;

  Map<String, String> get _headers {
    if (useRapidApi) {
      return {'x-rapidapi-key': apiKey, 'x-rapidapi-host': rapidApiHost};
    }
    return {'x-apisports-key': apiKey};
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = Uri.parse(baseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    final mergedPath = base.path.isEmpty
        ? '/$cleanPath'
        : (base.path.endsWith('/')
              ? '${base.path}$cleanPath'
              : '${base.path}/$cleanPath');

    return base.replace(
      path: mergedPath,
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final resp = await _http.get(_uri(path, query: query), headers: _headers);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiFootballHttpException(resp.statusCode, resp.body);
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiFootballFormatException('JSON root not an object', resp.body);
    }

    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      throw ApiFootballApiException(errors.toString());
    }

    return decoded;
  }

  void close() => _http.close();
}
