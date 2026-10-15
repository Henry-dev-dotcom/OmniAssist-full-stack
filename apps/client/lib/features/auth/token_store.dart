import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the refresh token. Access tokens stay in memory only (Spec 9.1).
abstract interface class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _key = 'omni.refresh_token';

  @override
  Future<String?> readRefreshToken() => _s.read(key: _key);
  @override
  Future<void> writeRefreshToken(String token) =>
      _s.write(key: _key, value: token);
  @override
  Future<void> clear() => _s.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  String? _token;
  @override
  Future<String?> readRefreshToken() async => _token;
  @override
  Future<void> writeRefreshToken(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}
