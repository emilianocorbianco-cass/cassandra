import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'api_football_exceptions.dart';

class ApiFootballClient {
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const int _maxAttempts = 3;

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
    final resp = await _getWithRetry(_uri(path, query: query));

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

  Future<http.Response> _getWithRetry(Uri uri) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _http
            .get(uri, headers: _headers)
            .timeout(_requestTimeout);

        final shouldRetry =
            _isRetryableStatus(response.statusCode) && attempt < _maxAttempts;
        if (!shouldRetry) return response;
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          throw ApiFootballException('Request timeout');
        }
      } on SocketException catch (e) {
        if (attempt >= _maxAttempts) {
          throw ApiFootballException('Network error: $e');
        }
      } on http.ClientException catch (e) {
        if (attempt >= _maxAttempts) {
          throw ApiFootballException('HTTP client error: $e');
        }
      }

      await Future<void>.delayed(_retryDelayFor(attempt));
    }
    throw ApiFootballException('Request failed');
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 429 || (statusCode >= 500 && statusCode <= 599);
  }

  Duration _retryDelayFor(int attempt) {
    final baseMs = 350;
    final factor = 1 << (attempt - 1); // 1,2,4
    return Duration(milliseconds: baseMs * factor);
  }

  void close() => _http.close();
}
