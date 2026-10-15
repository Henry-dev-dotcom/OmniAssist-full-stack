import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_error.dart';
import '../errors/error_codes.dart';

/// Supplies and renews the access token. Implemented by the auth repository.
abstract interface class TokenSource {
  String? get accessToken;

  /// Returns true when a new access token is available after the call.
  Future<bool> refresh();
}

/// Thin JSON client for the API envelope. Throws [AppError] for every failure,
/// including network loss, so callers handle one error type.
class ApiClient {
  ApiClient({required this.baseUrl, required http.Client client, this.tokens})
      : _http = client;

  final String baseUrl;
  final http.Client _http;
  TokenSource? tokens;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, Object body, {bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';
    final token = tokens?.accessToken;
    if (auth && token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 15)),
      );
    } on Exception {
      throw const AppError(
        code: ErrorCode.dependencyUnavailable,
        message: 'Cannot reach the server. Check your connection.',
        retryable: true,
      );
    }

    Map<String, dynamic> json = const {};
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      // Non-JSON body (proxy error page). Fall through to the status check.
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json['data'];

    final err = AppError.fromEnvelope(json);
    if (err.code == ErrorCode.unauthenticated &&
        auth &&
        !retried &&
        tokens != null &&
        await tokens!.refresh()) {
      return _send(method, path,
          query: query, body: body, auth: auth, retried: true);
    }
    throw err;
  }
}
