import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class DriveNotConfiguredException implements Exception {
  const DriveNotConfiguredException();

  @override
  String toString() =>
      'Google Drive is not set up in this app build yet (missing OAuth client id).';
}

/// Google sign-in limited to the `drive.file` scope: the app sees only the
/// files it created, nothing else in the user's Drive (PRD D1 step 2).
class GoogleDriveAuth {
  static const scopes = ['https://www.googleapis.com/auth/drive.file'];

  static Future<void>? _initialized;

  Future<void> _ensureInitialized() {
    if (!AppConfig.driveConfigured) {
      return Future.error(const DriveNotConfiguredException());
    }
    return _initialized ??= GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleServerClientId,
    );
  }

  /// Interactive: account picker + Drive permission. Returns the email.
  Future<String> connect() async {
    await _ensureInitialized();
    final account =
        await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await account.authorizationClient.authorizeScopes(scopes);
    return account.email;
  }

  /// Interactive sign-in only, used to prove account ownership when the
  /// PIN is forgotten (PRD AU-05). Returns the email.
  Future<String> verifyAccount() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    return account.email;
  }

  /// HTTP client with a Drive access token, or null if the user has to sign
  /// in again. Never shows UI unless [interactive] is true, so it is safe in
  /// the background backup job.
  Future<http.Client?> client({bool interactive = false}) async {
    await _ensureInitialized();
    GoogleSignInAccount? account;
    try {
      account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      account = null;
    }
    final authorization =
        account?.authorizationClient ?? GoogleSignIn.instance.authorizationClient;
    final headers = await authorization.authorizationHeaders(
      scopes,
      promptIfNecessary: interactive,
    );
    if (headers == null) return null;
    return _HeaderClient(headers);
  }

  Future<void> disconnect() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.disconnect();
  }
}

class _HeaderClient extends http.BaseClient {
  _HeaderClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
