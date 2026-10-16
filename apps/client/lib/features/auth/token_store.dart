import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the refresh token and the last session's ids (user and workspace), so a
/// signed-in user can open local data offline (Spec 4.1). Access tokens stay in memory.
abstract interface class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);

  /// "userId workspaceId", or null.
  Future<String?> readSession();
  Future<void> writeSession(String value);

  /// Forgets the token and the session.
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _key = 'omni.refresh_token';
  static const _sessionKey = 'omni.session';

  @override
  Future<String?> readRefreshToken() => _s.read(key: _key);
  @override
  Future<void> writeRefreshToken(String token) =>
      _s.write(key: _key, value: token);
  @override
  Future<String?> readSession() => _s.read(key: _sessionKey);
  @override
  Future<void> writeSession(String value) =>
      _s.write(key: _sessionKey, value: value);
  @override
  Future<void> clear() async {
    await _s.delete(key: _key);
    await _s.delete(key: _sessionKey);
  }
}

class MemoryTokenStore implements TokenStore {
  String? _token;
  String? _session;
  @override
  Future<String?> readRefreshToken() async => _token;
  @override
  Future<void> writeRefreshToken(String token) async => _token = token;
  @override
  Future<String?> readSession() async => _session;
  @override
  Future<void> writeSession(String value) async => _session = value;
  @override
  Future<void> clear() async => _token = _session = null;
}
