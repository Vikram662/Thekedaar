abstract final class AppConfig {
  static const appVersion = '0.1.0';

  /// Web OAuth client id from Google Cloud (PRD D-7), passed at build time:
  /// `flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get driveConfigured => googleServerClientId.isNotEmpty;
}
