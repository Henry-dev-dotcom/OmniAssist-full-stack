import '../../core/errors/app_error.dart';
import '../../core/errors/error_codes.dart';
import '../../core/net/api_client.dart';
import '../../core/result/result.dart';
import 'token_store.dart';

class Session {
  const Session({required this.userId, required this.workspaceId});
  final String userId;
  final String workspaceId;
}

class AuthRepository implements TokenSource {
  AuthRepository(this._api, this._store) {
    _api.tokens = this;
  }
  final ApiClient _api;
  final TokenStore _store;
  String? _access;

  @override
  String? get accessToken => _access;

  Future<void> _adopt(Map<String, dynamic> d) async {
    _access = d['access_token'] as String;
    final r = d['refresh_token'] as String?;
    if (r != null) await _store.writeRefreshToken(r);
  }

  /// Restores a session from the stored refresh token, if any. Never throws:
  /// offline start-up must still open the local data.
  @override
  Future<bool> refresh() async {
    final stored = await _store.readRefreshToken();
    if (stored == null) return false;
    try {
      final d = await _api.post('/auth/refresh', {
        'refresh_token': stored,
      }, auth: false) as Map<String, dynamic>;
      await _adopt(d);
      return true;
    } on AppError catch (e) {
      // Only a rejected token ends the session; a network error keeps it.
      if (e.code == ErrorCode.unauthenticated) await _store.clear();
      return false;
    }
  }

  Future<Result<Session>> signIn(String email, String password) =>
      _start('/auth/login', {'email': email, 'password': password});

  Future<Result<Session>> register(
    String email,
    String password,
    String displayName,
  ) => _start('/auth/register', {
    'email': email,
    'password': password,
    'display_name': displayName,
  });

  Future<Result<Session>> _start(String path, Map<String, Object> body) async {
    try {
      final d =
          await _api.post(path, body, auth: false) as Map<String, dynamic>;
      await _adopt(d);
      return Ok(await _loadSession());
    } on AppError catch (e) {
      return Err(e);
    }
  }

  Future<Result<Session>> restore() async {
    if (_access == null && !await refresh()) {
      return const Err(
        AppError(
          code: ErrorCode.unauthenticated,
          message: 'Sign in to continue.',
        ),
      );
    }
    try {
      return Ok(await _loadSession());
    } on AppError catch (e) {
      return Err(e);
    }
  }

  Future<void> signOut() async {
    final stored = await _store.readRefreshToken();
    try {
      if (stored != null && _access != null) {
        await _api.post('/auth/logout', {'refresh_token': stored});
      }
    } on AppError {
      // Server unreachable: still sign out locally.
    }
    _access = null;
    await _store.clear();
  }

  /// Drops tokens without calling the server (the account is already gone).
  Future<void> forget() async {
    _access = null;
    await _store.clear();
  }

  /// First sign-in creates a default workspace so the app always has a scope.
  Future<Session> _loadSession() async {
    final me = await _api.get('/me') as Map<String, dynamic>;
    final list = await _api.get('/workspaces') as List<dynamic>;
    final ws = list.isNotEmpty
        ? list.first as Map<String, dynamic>
        : await _api.post('/workspaces', {'name': 'Personal'})
              as Map<String, dynamic>;
    return Session(userId: me['id'] as String, workspaceId: ws['id'] as String);
  }
}
