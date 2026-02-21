import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cassandra/services/api_football/api_football_client.dart';
import 'package:cassandra/services/api_football/api_football_exceptions.dart';

void main() {
  test('retries on 5xx and succeeds', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts += 1;
      if (attempts < 3) {
        return http.Response('{"error":"temporary"}', 503);
      }
      return http.Response('{"response":[]}', 200);
    });
    final api = ApiFootballClient(apiKey: 'k', httpClient: client);

    final json = await api.getJson('fixtures');

    expect(attempts, 3);
    expect(json['response'], isA<List<dynamic>>());
  });

  test('does not retry on non-retryable 4xx', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts += 1;
      return http.Response('{"error":"bad request"}', 400);
    });
    final api = ApiFootballClient(apiKey: 'k', httpClient: client);

    await expectLater(
      api.getJson('fixtures'),
      throwsA(isA<ApiFootballHttpException>()),
    );
    expect(attempts, 1);
  });

  test('retries on 429 then throws after max attempts', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts += 1;
      return http.Response('{"error":"rate limit"}', 429);
    });
    final api = ApiFootballClient(apiKey: 'k', httpClient: client);

    await expectLater(
      api.getJson('fixtures'),
      throwsA(
        isA<ApiFootballHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          429,
        ),
      ),
    );
    expect(attempts, 3);
  });

  test('retries on client exception and recovers', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts += 1;
      if (attempts < 3) {
        throw http.ClientException('socket closed');
      }
      return http.Response('{"response":[{"id":1}]}', 200);
    });
    final api = ApiFootballClient(apiKey: 'k', httpClient: client);

    final json = await api.getJson('fixtures');

    expect(attempts, 3);
    expect(json['response'], isA<List<dynamic>>());
  });
}
