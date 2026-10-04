abstract final class AppConfig {
  static const appVersion = '0.1.0';
  static const appBuildNumber = 1;

  /// Web OAuth client id from Google Cloud (PRD D-7), passed at build time:
  /// `flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const subscriptionApiUrl =
      String.fromEnvironment('SUBSCRIPTION_API_URL');

  static bool get driveConfigured => googleServerClientId.isNotEmpty;
  static bool get subscriptionConfigured => subscriptionApiUrl.isNotEmpty;
}
