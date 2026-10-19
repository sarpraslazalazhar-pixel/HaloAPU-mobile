enum AppFlavor { staging, production }

class FlavorConfig {
  static const String _envFlavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'staging',
  );

  static AppFlavor get current =>
      _envFlavor == 'production' ? AppFlavor.production : AppFlavor.staging;

  static String get baseUrl => switch (current) {
    AppFlavor.staging => 'https://dev.haloapu.id/api',
    AppFlavor.production => 'https://haloapu.id/api',
  };

  static String get webUrl => switch (current) {
    AppFlavor.staging => 'https://dev.haloapu.id',
    AppFlavor.production => 'https://haloapu.id',
  };

  static String get appTitle => switch (current) {
    AppFlavor.staging => 'Halo APU Staging',
    AppFlavor.production => 'Halo APU',
  };

  static bool get isStaging => current == AppFlavor.staging;
}
