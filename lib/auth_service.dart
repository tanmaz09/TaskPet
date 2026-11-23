import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

/// Thrown when sign-in fails. [network] is true when the phone simply could
/// not reach Google (offline), so callers can retry later quietly.
class AuthException implements Exception {
  final String message;
  final bool network;
  AuthException(this.message, {this.network = false});

  @override
  String toString() => 'AuthException: $message';
}

class AuthSession {
  final String uid;
  final String idToken;
  final DateTime expiresAt;
  const AuthSession(this.uid, this.idToken, this.expiresAt);

  /// False in the last minute before expiry, so a request never starts with
  /// a token that is about to die.
  bool get isFresh =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 1)));
}

/// Anonymous Firebase sign-in over Google's web API (no native plugin, so no
/// Gradle changes). The phone gets an account id (uid) without the user
/// typing anything; the refresh token is kept in the app's private storage
/// so the same account is used on every launch.
class AuthService {
  static const _kRefresh = 'fb_refresh';
  static const _kUid = 'fb_uid';

  final String apiKey;
  final String _identityBase;
  final String _tokenBase;

  AuthService._({
    required this.apiKey,
    String identityBase = 'https://identitytoolkit.googleapis.com/v1',
    String tokenBase = 'https://securetoken.googleapis.com/v1',
  })  : _identityBase = identityBase,
        _tokenBase = tokenBase;

  static final AuthService instance =
      AuthService._(apiKey: FirebaseConfig.apiKey);

  /// For tests: point the service at a fake server.
  AuthService.forTesting({
    required this.apiKey,
    required String identityBase,
    required String tokenBase,
  })  : _identityBase = identityBase,
        _tokenBase = tokenBase;

  AuthSession? _session;
  Future<AuthSession>? _pending;

  bool get isConfigured =>
      apiKey.isNotEmpty && !apiKey.startsWith('YOUR_');

  /// The signed-in account id, or null before the first sign-in finishes.
  String? get uid => _session?.uid;

  /// Returns a valid session, signing in or refreshing the token if needed.
  /// Several callers at once share one request.
  Future<AuthSession> ensureSignedIn() {
    final s = _session;
    if (s != null && s.isFresh) return Future.value(s);
    return _pending ??= _signIn().whenComplete(() => _pending = null);
  }

  /// A valid ID token to send with a request.
  Future<String> idToken() async => (await ensureSignedIn()).idToken;

  /// Forgets the account on this phone (used when the account is deleted).
  Future<void> signOutLocal() async {
    _session = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRefresh);
    await p.remove(_kUid);
  }

  /// Deletes this phone's Firebase account for good, then forgets it
  /// locally. Already-deleted accounts count as success.
  Future<void> deleteAccount() async {
    final session = await ensureSignedIn();
    try {
      await _send(
        Uri.parse('$_identityBase/accounts:delete?key=$apiKey'),
        body: jsonEncode({'idToken': session.idToken}),
        contentType: 'application/json',
      );
    } on AuthException catch (e) {
      final gone = e.message.contains('USER_NOT_FOUND') ||
          e.message.contains('INVALID_ID_TOKEN');
      if (e.network || !gone) rethrow;
    }
    await signOutLocal();
  }

  // ------------------------------------------------------------ internals

  Future<AuthSession> _signIn() async {
    if (!isConfigured) {
      throw AuthException('Firebase is not configured yet');
    }
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kRefresh);

    if (stored != null && stored.isNotEmpty) {
      try {
        return await _refresh(stored);
      } on AuthException catch (e) {
        // Offline: keep the stored account and try again later.
        if (e.network) rethrow;
        // The account is gone or the token is dead: start a fresh account.
        await signOutLocal();
      }
    }
    return _signUp();
  }

  Future<AuthSession> _signUp() async {
    final json = await _send(
      Uri.parse('$_identityBase/accounts:signUp?key=$apiKey'),
      body: jsonEncode({'returnSecureToken': true}),
      contentType: 'application/json',
    );
    return _store(
      uid: json['localId'] as String,
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: json['expiresIn'],
    );
  }

  Future<AuthSession> _refresh(String refreshToken) async {
    final json = await _send(
      Uri.parse('$_tokenBase/token?key=$apiKey'),
      body: 'grant_type=refresh_token'
          '&refresh_token=${Uri.encodeQueryComponent(refreshToken)}',
      contentType: 'application/x-www-form-urlencoded',
    );
    return _store(
      uid: json['user_id'] as String,
      idToken: json['id_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'],
    );
  }

  Future<AuthSession> _store({
    required String uid,
    required String idToken,
    required String refreshToken,
    required Object? expiresIn,
  }) async {
    final seconds = int.tryParse('$expiresIn') ?? 3600;
    final session = AuthSession(
      uid,
      idToken,
      DateTime.now().add(Duration(seconds: seconds)),
    );
    _session = session;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRefresh, refreshToken);
    await p.setString(_kUid, uid);
    return session;
  }

  Future<Map<String, dynamic>> _send(
    Uri url, {
    required String body,
    required String contentType,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(url);
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();

      Map<String, dynamic> json = {};
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
      if (res.statusCode != 200) {
        final err = json['error'];
        final msg = err is Map ? err['message'] : null;
        throw AuthException('${msg ?? 'HTTP ${res.statusCode}'}');
      }
      return json;
    } on SocketException {
      throw AuthException('NETWORK', network: true);
    } on HandshakeException {
      throw AuthException('NETWORK', network: true);
    } on TimeoutException {
      throw AuthException('NETWORK', network: true);
    } finally {
      client.close();
    }
  }
}
