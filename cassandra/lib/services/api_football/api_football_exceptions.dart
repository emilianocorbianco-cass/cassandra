class ApiFootballException implements Exception {
  final String message;
  ApiFootballException(this.message);

  @override
  String toString() => 'ApiFootballException: $message';
}

class ApiFootballHttpException extends ApiFootballException {
  final int statusCode;
  final String responseBody;

  ApiFootballHttpException(this.statusCode, this.responseBody)
    : super('HTTP $statusCode');
}

class ApiFootballFormatException extends ApiFootballException {
  final String rawBody;

  ApiFootballFormatException(super.message, this.rawBody);
}

class ApiFootballApiException extends ApiFootballException {
  ApiFootballApiException(super.message);
}
