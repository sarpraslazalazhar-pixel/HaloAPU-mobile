import 'app_flavor.dart';

class ApiConfig {
  static String get defaultBaseUrl => FlavorConfig.baseUrl;
  static String get baseUrl => FlavorConfig.baseUrl;
  static Future<void> loadSavedBaseUrl() async {}
}
