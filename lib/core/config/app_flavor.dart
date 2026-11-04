enum AppFlavor { staging, production }

class FlavorConfig {
  static const String _envFlavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'staging',
  );

  static const String _customBaseUrl = String.fromEnvironment('BASE_URL');
  static const String _customWebUrl = String.fromEnvironment('WEB_URL');

  static AppFlavor get current =>
      _envFlavor == 'production' ? AppFlavor.production : AppFlavor.staging;

  static String get baseUrl {
    if (_customBaseUrl.isNotEmpty) return _customBaseUrl;
    return switch (current) {
      AppFlavor.staging => 'https://dev.haloapu.id/api',
      AppFlavor.production => 'https://haloapu.apudev.id/api',
    };
  }

  static String get webUrl {
    if (_customWebUrl.isNotEmpty) return _customWebUrl;
    return switch (current) {
      AppFlavor.staging => 'https://dev.haloapu.id',
      AppFlavor.production => 'https://haloapu.apudev.id',
    };
  }
  static String get appTitle => switch (current) {
    AppFlavor.staging => 'Halo APU Staging',
    AppFlavor.production => 'Halo APU',
  };

  static bool get isStaging => current == AppFlavor.staging;
}
