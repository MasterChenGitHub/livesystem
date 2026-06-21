abstract final class AppServerConfig {
  static const String serverScheme = String.fromEnvironment(
    'SERVER_SCHEME',
    defaultValue: 'http',
  );

  static const String serverHost = String.fromEnvironment(
    'SERVER_HOST',
    defaultValue: '42.121.222.6',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '$serverScheme://$serverHost/api',
  );

  static const String webrtcServerUrl = String.fromEnvironment(
    'WEBRTC_SERVER_URL',
    defaultValue: '$serverScheme://$serverHost',
  );
}
